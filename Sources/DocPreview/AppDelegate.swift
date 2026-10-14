import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandlerWithReply, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var scheme: SchemeHandler!
    private var workspace: Workspace?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let uiRoot = Bundle.module.resourceURL!.appendingPathComponent("ui")
        scheme = SchemeHandler(uiRoot: uiRoot)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(scheme, forURLScheme: "docpreview")
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "native")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "DocPreview"
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("DocPreviewMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 起動引数（最初の非オプション引数）をパスとして扱う。なければ選択ダイアログ。
        let arg = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
        if let arg, let ws = Workspace(path: arg) {
            open(ws)
        } else {
            openPanel()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ sender: NSApplication, open urls: [URL]) {
        if let url = urls.first, let ws = Workspace(path: url.path) { open(ws) }
    }

    // MARK: - Workspace

    private func open(_ ws: Workspace) {
        workspace = ws
        scheme.workspace = ws
        window.title = "DocPreview — \(ws.root.lastPathComponent)"
        webView.load(URLRequest(url: URL(string: "docpreview://app/ui/index.html")!))
    }

    @objc private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "プレビューするフォルダ、または Markdown / HTML ファイルを選択"
        if panel.runModal() == .OK, let url = panel.url, let ws = Workspace(path: url.path) {
            open(ws)
        } else if workspace == nil {
            NSApp.terminate(nil)
        }
    }

    // MARK: - JS bridge

    func userContentController(
        _ ucc: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
            return replyHandler(nil, "bad message")
        }
        guard let ws = workspace else { return replyHandler(nil, "no workspace") }
        let store = CommentStore(root: ws.root)

        switch action {
        case "init":
            replyHandler([
                "name": ws.root.lastPathComponent,
                "root": ws.root.path,
                "initialFile": ws.initialFile.flatMap(ws.relativePath(of:)) as Any,
                "tree": ws.tree(),
                "comments": store.load(),
            ], nil)
        case "tree":
            replyHandler(ws.tree(), nil)
        case "poll":
            var mtime = 0.0
            if let rel = body["path"] as? String, !rel.isEmpty,
               let date = try? FileManager.default.attributesOfItem(
                atPath: ws.root.appendingPathComponent(rel).path)[.modificationDate] as? Date {
                mtime = date.timeIntervalSince1970
            }
            replyHandler(["mtime": mtime, "tree": treeSignature(ws)], nil)
        case "saveComments":
            store.save(body["json"] as? String ?? "[]")
            replyHandler(true, nil)
        case "openPanel":
            DispatchQueue.main.async { self.openPanel() }
            replyHandler(true, nil)
        case "launchClaude":
            let prompt = body["prompt"] as? String ?? ""
            DispatchQueue.global().async {
                do {
                    try ClaudeLauncher.launch(prompt: prompt, cwd: ws.root)
                    replyHandler(true, nil)
                } catch {
                    replyHandler(nil, error.localizedDescription)
                }
            }
        default:
            replyHandler(nil, "unknown action")
        }
    }

    private func treeSignature(_ ws: Workspace) -> Int {
        func flatten(_ node: [String: Any]) -> [String] {
            let kids = (node["children"] as? [[String: Any]]) ?? []
            return [node["path"] as? String ?? ""] + kids.flatMap(flatten)
        }
        var h = Hasher()
        flatten(ws.tree()).forEach { h.combine($0) }
        return h.finalize()
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
        add("DocPreview", [
            NSMenuItem(title: "DocPreview を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ])
        let open = NSMenuItem(title: "開く…", action: #selector(openPanel), keyEquivalent: "o")
        open.target = self
        add("ファイル", [open])
        add("編集", [
            NSMenuItem(title: "取り消す", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        NSApp.mainMenu = main
    }
}
