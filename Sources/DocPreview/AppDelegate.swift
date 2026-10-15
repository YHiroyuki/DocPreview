import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 開いているタブ（ウィンドウ）。タブごとに独立したワークスペースを持つ。
    private var docs: [DocWindow] = []

    private var activeDoc: DocWindow? { docs.first { $0.window.isKeyWindow } ?? docs.last }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)

        // 起動引数（最初の非オプション引数）をパスとして扱う。なければ選択ダイアログ。
        let arg = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
        if let arg, openTarget(path: arg) {
            runDebugHooks()
        } else {
            // Finder / `open` 経由の起動では、このあと application(_:open:) でファイルが渡される
            DispatchQueue.main.async { [self] in
                if docs.isEmpty { openPanel() }
                runDebugHooks()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ sender: NSApplication, open urls: [URL]) {
        urls.forEach { openTarget(path: $0.path) }
    }

    // MARK: - Tabs

    /// パスを新しいタブで開く。同じ対象がすでに開いていればそのタブを前面にする。
    @discardableResult
    private func openTarget(path: String) -> Bool {
        guard let ws = Workspace(path: path) else { return false }
        let target = ws.initialFile
            ?? ws.initialDir.map { ws.root.appendingPathComponent($0) }
            ?? ws.root
        if let existing = docs.first(where: { $0.target == target }) {
            existing.window.makeKeyAndOrderFront(nil)
            return true
        }

        let host = activeDoc?.window
        let doc = DocWindow(workspace: ws, target: target, isFirst: docs.isEmpty)
        doc.onClose = { [weak self] d in self?.docs.removeAll { $0 === d } }
        doc.onDrop = { [weak self] urls in urls.forEach { self?.openTarget(path: $0.path) } }
        docs.append(doc)
        if let host { host.addTabbedWindow(doc.window, ordered: .above) }
        doc.window.makeKeyAndOrderFront(nil)
        doc.start()
        return true
    }

    @objc func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "プレビューするフォルダ、または Markdown / HTML ファイルを選択"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            panel.urls.forEach { openTarget(path: $0.path) }
        } else if docs.isEmpty {
            NSApp.terminate(nil)
        }
    }

    /// タブバーの「+」ボタン
    @objc func newWindowForTab(_ sender: Any?) { openPanel() }

    @objc private func showSettings() {
        activeDoc?.webView.evaluateJavaScript("openSettings()")
    }

    // MARK: - Menu

    private func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        let prefs = NSMenuItem(title: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        add("DocPreview", [
            prefs,
            NSMenuItem(title: "DocPreview を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ])
        let open = NSMenuItem(title: "開く…", action: #selector(openPanel), keyEquivalent: "o")
        open.target = self
        add("ファイル", [open, .separator(), NSMenuItem(title: "タブを閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")])
        func findItem(_ title: String, _ js: String, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = BlockItem(title: title, key: key) { [weak self] in self?.activeDoc?.webView.evaluateJavaScript(js) }
            item.keyEquivalentModifierMask = mods
            return item
        }
        add("編集", [
            NSMenuItem(title: "取り消す", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
            .separator(),
            findItem("検索…", "openFind()", "f"),
            findItem("次を検索", "findNext()", "g"),
            findItem("前を検索", "findPrev()", "g", [.command, .shift]),
        ])
        add("ウインドウ", [
            NSMenuItem(title: "次のタブ", action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "}"),
            NSMenuItem(title: "前のタブ", action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "{"),
            .separator(),
            NSMenuItem(title: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        ])
        NSApp.mainMenu = main
        NSApp.windowsMenu = main.items.last?.submenu
    }
}

// MARK: - 動作検証用フック（環境変数）
extension AppDelegate {
    /// DOCPREVIEW_EVAL=<js> : N 秒後に JS を評価して標準出力へ。
    /// DOCPREVIEW_SNAPSHOT=<png パス> : N 秒後にスナップショットを保存。
    /// DOCPREVIEW_DELAY=<秒> (既定 3)。いずれか指定時は完了後に終了する。
    fileprivate func runDebugHooks() {
        let env = ProcessInfo.processInfo.environment
        guard env["DOCPREVIEW_EVAL"] != nil || env["DOCPREVIEW_SNAPSHOT"] != nil else { return }
        let delay = Double(env["DOCPREVIEW_DELAY"] ?? "") ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard let webView = docs.first?.webView else { return NSApp.terminate(nil) }
            func finish() { NSApp.terminate(nil) }
            func snapshot() {
                guard let path = env["DOCPREVIEW_SNAPSHOT"] else { return finish() }
                webView.takeSnapshot(with: nil) { image, _ in
                    if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                    finish()
                }
            }
            if let js = env["DOCPREVIEW_EVAL"] {
                webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let v): print("EVAL:", v ?? "nil")
                    case .failure(let e): print("EVAL ERROR:", e)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { snapshot() }
                }
            } else {
                snapshot()
            }
        }
    }
}

/// クロージャを実行するメニュー項目
final class BlockItem: NSMenuItem {
    private let block: () -> Void
    init(title: String, key: String, block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { block() }
}
