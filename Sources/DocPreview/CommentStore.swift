import CryptoKit
import Foundation

/// コメントをルートディレクトリごとに JSON で永続化する。
/// 保存先: ~/Library/Application Support/DocPreview/comments/<root のハッシュ>.json
struct CommentStore {
    let root: URL

    private var file: URL {
        let digest = SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        return Self.supportDir.appendingPathComponent("comments/\(digest).json")
    }

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DocPreview")
    }

    func load() -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? "[]"
    }

    func save(_ json: String) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? json.write(to: file, atomically: true, encoding: .utf8)
    }
}
