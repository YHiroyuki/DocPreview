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

    /// ルート配下の対応ファイルのツリー（JSON 互換の辞書）。重いので UI スレッドでは呼ばないこと。
    func tree() -> [String: Any] {
        let paths = isGitRoot ? (gitFiles() ?? scanFiles()) : scanFiles()
        return Self.buildTree(name: root.lastPathComponent, paths: paths)
    }

    private static func isDocument(_ rel: String) -> Bool {
        supportedExtensions.contains((rel as NSString).pathExtension.lowercased())
    }

    /// git 管理下なら `git ls-files` を使う。.gitignore を尊重でき、全ディレクトリを歩くより圧倒的に速い。
    private func gitFiles() -> [String]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "core.quotepath=off", "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()  // 先に読み切らないとパイプが詰まる
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let fm = FileManager.default
        return data.split(separator: 0).compactMap { chunk -> String? in
            guard let rel = String(data: chunk, encoding: .utf8), Self.isDocument(rel),
                  !rel.split(separator: "/").dropLast().contains(where: { $0.hasPrefix(".") }),
                  fm.fileExists(atPath: root.appendingPathComponent(rel).path)  // 削除済みの追跡ファイルを除く
            else { return nil }
            return rel
        }
    }

    /// git 管理外のときのフォールバック。重いディレクトリは降りずにスキップする。
    private func scanFiles() -> [String] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [String] = []
        let prefix = root.path + "/"
        for case let url as URL in e {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if Self.ignoredNames.contains(url.lastPathComponent) { e.skipDescendants() }
            } else if Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                result.append(String(url.path.dropFirst(prefix.count)))
                if result.count >= 5000 { break }
            }
        }
        return result
    }

    /// 相対パスの一覧から、ディレクトリ→ファイルの順に並べたツリーを作る。
    static func buildTree(name: String, paths: [String]) -> [String: Any] {
        final class Node {
            var dirs: [String: Node] = [:]
            var files: [String] = []
        }
        let rootNode = Node()
        for path in paths {
            let parts = path.split(separator: "/").map(String.init)
            var node = rootNode
            for dir in parts.dropLast() {
                if let n = node.dirs[dir] { node = n } else { let n = Node(); node.dirs[dir] = n; node = n }
            }
            node.files.append(parts.last!)
        }
        func sorted(_ names: [String]) -> [String] {
            names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        func convert(_ node: Node, rel: String) -> [[String: Any]] {
            let dirs = sorted(Array(node.dirs.keys)).map { name -> [String: Any] in
                let path = rel.isEmpty ? name : rel + "/" + name
                return ["name": name, "path": path, "type": "dir", "children": convert(node.dirs[name]!, rel: path)]
            }
            let files = sorted(node.files).map { name -> [String: Any] in
                ["name": name, "path": rel.isEmpty ? name : rel + "/" + name, "type": "file"]
            }
            return dirs + files
        }
        return ["name": name, "path": "", "type": "dir", "children": convert(rootNode, rel: "")]
    }
}
