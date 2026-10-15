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
    static let ignoredNames: Set<String> = ["node_modules", ".git", ".build", "build", "dist", "target", "Pods"]

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

    /// ルート配下の対応ファイルのツリーを JSON 互換の辞書で返す。空ディレクトリは除く。
    func tree() -> [String: Any] {
        var budget = 5000
        let children = scan(root, rel: "", budget: &budget)
        return ["name": root.lastPathComponent, "path": "", "type": "dir", "children": children]
    }

    private func scan(_ dir: URL, rel: String, budget: inout Int) -> [[String: Any]] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var dirs: [[String: Any]] = []
        var files: [[String: Any]] = []
        for item in items.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard budget > 0 else { break }
            let name = item.lastPathComponent
            let itemRel = rel.isEmpty ? name : rel + "/" + name
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if Self.ignoredNames.contains(name) { continue }
                let kids = scan(item, rel: itemRel, budget: &budget)
                if !kids.isEmpty {
                    dirs.append(["name": name, "path": itemRel, "type": "dir", "children": kids])
                }
            } else if Self.supportedExtensions.contains(item.pathExtension.lowercased()) {
                budget -= 1
                files.append(["name": name, "path": itemRel, "type": "file"])
            }
        }
        return dirs + files
    }
}
