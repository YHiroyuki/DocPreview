import Foundation

/// cmux で新しいワークスペースを開き、Claude Code にコメント内容を渡して起動する。
enum ClaudeLauncher {
    enum LaunchError: LocalizedError {
        case cmuxNotFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cmuxNotFound: return "cmux が見つかりません（/Applications/cmux.app を確認してください）"
            case .failed(let m): return "cmux の起動に失敗しました: \(m)"
            }
        }
    }

    static func cmuxPath() -> String? {
        let candidates = [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            "\(NSHomeDirectory())/Applications/cmux.app/Contents/Resources/bin/cmux",
            "/opt/homebrew/bin/cmux",
            "/usr/local/bin/cmux",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// - Parameters:
    ///   - prompt: Claude Code に渡す指示文
    ///   - cwd: ワークスペースのルート（Claude Code の作業ディレクトリ）
    static func launch(prompt: String, cwd: URL) throws {
        guard let cmux = cmuxPath() else { throw LaunchError.cmuxNotFound }

        // 長文・特殊文字を安全に渡すため、プロンプトはファイル経由にする。
        let dir = CommentStore.supportDir.appendingPathComponent("prompts")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let promptFile = dir.appendingPathComponent("prompt-\(Int(Date().timeIntervalSince1970)).md")
        try prompt.write(to: promptFile, atomically: true, encoding: .utf8)

        let command = "claude \"$(cat \(shellQuote(promptFile.path)))\""

        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmux)
        p.arguments = ["new-workspace", "--name", "DocPreview: Claude", "--cwd", cwd.path, "--command", command]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LaunchError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // cmux アプリを前面に出す
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "cmux"]
        try? open.run()
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
