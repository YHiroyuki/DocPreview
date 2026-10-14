import Foundation

/// 表示対象のルートディレクトリと、最初に開くファイルを表す。
struct Workspace {
    let root: URL
    let initialFile: URL?

    static let supportedExtensions: Set<String> = ["md", "markdown", "html", "htm"]
    static let ignoredNames: Set<String> = ["node_modules", ".git", ".build", "build", "dist", "target", "Pods"]

    /// パスがディレクトリならそれをルートに、ファイルならその親ディレクトリをルートにする。
    init?(path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            root = url
            initialFile = nil
        } else {
            root = url.deletingLastPathComponent()
            initialFile = url
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
