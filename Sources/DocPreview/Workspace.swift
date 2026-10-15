import Foundation

/// 表示対象のルートディレクトリと、最初に開くファイルを表す。
struct Workspace {
    let root: URL
    let initialFile: URL?
    /// ディレクトリ指定で開いたときの、ルートからの相対パス（ツリーで展開して最初に表示する場所）
    let initialDir: String?
    /// ルートが git ルートかどうか
    let isGitRoot: Bool

    static let supportedExtensions: Set<String> = ["md", "markdown", "html", "htm"]
    static let ignoredNames: Set<String> = ["node_modules", ".git", ".build", "build", "dist", "target", "Pods", "vendor", ".gradle", ".venv", "venv", "__pycache__"]

    /// パスから決める。ルートは次のとおり。
    /// - git 管理下なら、ディレクトリ・ファイルを問わず git リポジトリのルート
    /// - それ以外は、ディレクトリならそれ自体、ファイルならその親ディレクトリ
    init?(path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        let base = isDir.boolValue ? url : url.deletingLastPathComponent()
        let gitRoot = Self.findGitRoot(from: base)
        root = gitRoot ?? base
        isGitRoot = gitRoot != nil
        initialFile = isDir.boolValue ? nil : url
        if isDir.boolValue, root.path != url.path {
            initialDir = String(url.path.dropFirst(root.path.count + 1))
        } else {
            initialDir = nil
        }
    }

    /// `.git`（ディレクトリ、worktree/submodule ではファイル）を上に辿って探す。
    static func findGitRoot(from start: URL) -> URL? {
        var dir = start.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    func relativePath(of url: URL) -> String? {
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(base) else { return nil }
        return String(url.path.dropFirst(base.count))
    }

    /// `.` 始まりのフォルダ/ファイルがツリーに含まれるか。初期ファイルが隠しパス配下なら表示が必要。
    var initialFileIsHidden: Bool {
        guard let f = initialFile, let rel = relativePath(of: f) else { return false }
        return rel.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// ルート配下の対応ファイルのツリー（JSON 互換の辞書）。重いので UI スレッドでは呼ばないこと。
    /// `showHidden` のとき `.` 始まりのフォルダは中身を読まない遅延ロード用ノード（`lazy: true`）として入れる。
    func tree(showHidden: Bool) -> [String: Any] {
        let found = collect(under: "", showHidden: showHidden)
        return ["name": root.lastPathComponent, "path": "", "type": "dir",
                "children": Self.buildChildren(base: "", files: found.files, lazyDirs: found.lazyDirs)]
    }

    /// 遅延ロード用。指定ディレクトリ配下（隠しフォルダを含む）の子ノードを返す。
    func subtree(_ rel: String) -> [[String: Any]] {
        let found = collect(under: rel, showHidden: true)
        return Self.buildChildren(base: rel, files: found.files, lazyDirs: found.lazyDirs)
    }

    private static func isDocument(_ rel: String) -> Bool {
        supportedExtensions.contains((rel as NSString).pathExtension.lowercased())
    }

    private func collect(under rel: String, showHidden: Bool) -> (files: [String], lazyDirs: Set<String>) {
        if isGitRoot, let r = gitCollect(under: rel, showHidden: showHidden) { return r }
        return scanCollect(under: rel, showHidden: showHidden)
    }

    /// git 管理下なら `git ls-files` を使う。.gitignore を尊重でき、全ディレクトリを歩くより圧倒的に速い。
    private func gitCollect(under rel: String, showHidden: Bool) -> (files: [String], lazyDirs: Set<String>)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        var args = ["-C", root.path, "-c", "core.quotepath=off", "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        if !rel.isEmpty { args += ["--", rel] }
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()  // 先に読み切らないとパイプが詰まる
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }

        let fm = FileManager.default
        let baseCount = rel.isEmpty ? 0 : rel.split(separator: "/").count
        var files: [String] = []
        var lazy = Set<String>()
        for chunk in data.split(separator: 0) {
            guard let path = String(data: chunk, encoding: .utf8), Self.isDocument(path) else { continue }
            let parts = path.split(separator: "/").map(String.init)
            // rel より下の最初の「.」始まりのディレクトリ
            if let i = parts.dropLast().enumerated().first(where: { $0.offset >= baseCount && $0.element.hasPrefix(".") })?.offset {
                if showHidden { lazy.insert(parts[0...i].joined(separator: "/")) }
                continue
            }
            if parts.last!.hasPrefix(".") && !showHidden { continue }
            if fm.fileExists(atPath: root.appendingPathComponent(path).path) { files.append(path) }  // 削除済みの追跡ファイルを除く
        }
        return (files, lazy)
    }

    /// git 管理外のときのフォールバック。重いディレクトリは降りずにスキップする。
    private func scanCollect(under rel: String, showHidden: Bool) -> (files: [String], lazyDirs: Set<String>) {
        let fm = FileManager.default
        let start = rel.isEmpty ? root : root.appendingPathComponent(rel)
        guard let e = fm.enumerator(at: start, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return ([], []) }
        var files: [String] = []
        var lazy = Set<String>()
        let prefix = root.path + "/"
        for case let url as URL in e {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let path = String(url.path.dropFirst(prefix.count))
            if isDir {
                if name == ".git" || Self.ignoredNames.contains(name) { e.skipDescendants(); continue }
                if name.hasPrefix(".") {
                    e.skipDescendants()
                    if showHidden { lazy.insert(path) }
                }
            } else if Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                if name.hasPrefix(".") && !showHidden { continue }
                files.append(path)
                if files.count >= 5000 { break }
            }
        }
        return (files, lazy)
    }

    /// `base` 配下の相対パス一覧から、ディレクトリ→ファイルの順に並べた子ノードを作る。
    static func buildChildren(base: String, files: [String], lazyDirs: Set<String>) -> [[String: Any]] {
        final class Node {
            var dirs: [String: Node] = [:]
            var files: [String] = []
            var lazy = false
        }
        let rootNode = Node()
        let baseCount = base.isEmpty ? 0 : base.split(separator: "/").count
        func descend(_ parts: [String]) -> Node {
            var node = rootNode
            for dir in parts.dropFirst(baseCount) {
                if let n = node.dirs[dir] { node = n } else { let n = Node(); node.dirs[dir] = n; node = n }
            }
            return node
        }
        for path in files {
            let parts = path.split(separator: "/").map(String.init)
            descend(Array(parts.dropLast())).files.append(parts.last!)
        }
        for dir in lazyDirs { descend(dir.split(separator: "/").map(String.init)).lazy = true }

        func sorted(_ names: [String]) -> [String] {
            names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        func convert(_ node: Node, rel: String) -> [[String: Any]] {
            let dirs = sorted(Array(node.dirs.keys)).map { name -> [String: Any] in
                let path = rel.isEmpty ? name : rel + "/" + name
                let child = node.dirs[name]!
                var d: [String: Any] = ["name": name, "path": path, "type": "dir", "children": convert(child, rel: path)]
                if child.lazy { d["lazy"] = true }
                return d
            }
            let fs = sorted(node.files).map { name -> [String: Any] in
                ["name": name, "path": rel.isEmpty ? name : rel + "/" + name, "type": "file"]
            }
            return dirs + fs
        }
        return convert(rootNode, rel: base)
    }
}
