import AppKit
import WebKit

/// 1 タブ（= 1 ウィンドウ）分。ワークスペース・ツリーのキャッシュ・WebView・JS ブリッジを持つ。
final class DocWindow: NSObject, WKScriptMessageHandlerWithReply, WKUIDelegate, NSWindowDelegate {
    let window: NSWindow
    let webView: DropWebView
    let workspace: Workspace
    /// 開く対象（ファイル、またはディレクトリ）。同じ対象を二重に開かないための識別に使う。
    let target: URL
    var onClose: ((DocWindow) -> Void)?
    var onDrop: (([URL]) -> Void)?

    private let scheme: SchemeHandler
    private let treeCache: TreeCache

    init(workspace ws: Workspace, target: URL, isFirst: Bool) {
        workspace = ws
        self.target = target

        let uiRoot = Bundle.module.resourceURL!.appendingPathComponent("ui")
        scheme = SchemeHandler(uiRoot: uiRoot)
        scheme.workspace = ws

        let hidden = ws.initialFileIsHidden || UserDefaults.standard.bool(forKey: "showHidden")
        treeCache = TreeCache(workspace: ws, showHidden: hidden)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(scheme, forURLScheme: "docpreview")
        webView = DropWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = ws.initialFile?.lastPathComponent ?? ws.root.lastPathComponent
        window.contentView = webView
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "DocPreview"
        window.isReleasedWhenClosed = false
        if isFirst {
            window.center()
            window.setFrameAutosaveName("DocPreviewMain")
        }

        super.init()
        webView.uiDelegate = self
        webView.onDrop = { [weak self] urls in self?.onDrop?(urls) }
        window.delegate = self
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "native")
    }

    func start() {
        treeCache.refresh(force: true)  // 先に走査を始めておく
        webView.load(URLRequest(url: URL(string: "docpreview://app/ui/index.html")!))
    }

    func windowWillClose(_ notification: Notification) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "native", contentWorld: .page)
        onClose?(self)
    }

    // MARK: - JS bridge

    func userContentController(
        _ ucc: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
            return replyHandler(nil, "bad message")
        }
        let ws = workspace, cache = treeCache
        let store = CommentStore(root: ws.root)

        switch action {
        case "init":
            let comments = store.load()
            cache.tree { tree in
                replyHandler([
                    "name": ws.root.lastPathComponent,
                    "root": ws.root.path,
                    "initialFile": ws.initialFile.flatMap(ws.relativePath(of:)) as Any,
                    "initialDir": ws.initialDir as Any,
                    "isGit": ws.isGitRoot,
                    "showHidden": cache.isShowingHidden,
                    "tree": tree,
                    "comments": comments,
                    "settings": [
                        "theme": UserDefaults.standard.string(forKey: "theme") ?? "light",
                        "fontSize": UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 16,
                        "leftWidth": UserDefaults.standard.object(forKey: "leftWidth") as? Int ?? 260,
                        "rightWidth": UserDefaults.standard.object(forKey: "rightWidth") as? Int ?? 300,
                    ],
                ], nil)
            }
        case "saveSettings":
            if let s = body["settings"] as? [String: Any] {
                if let t = s["theme"] as? String { UserDefaults.standard.set(t, forKey: "theme") }
                for key in ["fontSize", "leftWidth", "rightWidth"] {
                    if let v = s[key] as? Int { UserDefaults.standard.set(v, forKey: key) }
                }
            }
            replyHandler(true, nil)
        case "setShowHidden":
            let value = body["value"] as? Bool ?? false
            UserDefaults.standard.set(value, forKey: "showHidden")
            cache.setShowHidden(value) { replyHandler($0, nil) }
        case "children":
            cache.subtree(body["path"] as? String ?? "") { replyHandler($0, nil) }
        case "tree":
            cache.tree { replyHandler($0, nil) }
        case "poll":
            var mtime = 0.0
            if let rel = body["path"] as? String, !rel.isEmpty,
               let date = try? FileManager.default.attributesOfItem(
                atPath: ws.root.appendingPathComponent(rel).path)[.modificationDate] as? Date {
                mtime = date.timeIntervalSince1970
            }
            cache.refresh()  // 3 秒以上経っていれば裏で再走査
            replyHandler(["mtime": mtime, "tree": cache.cachedSignature], nil)
        case "saveComments":
            store.save(body["json"] as? String ?? "[]")
            replyHandler(true, nil)
        case "title":
            // タブの表示名は、開いているファイル名に追従させる
            if let name = body["name"] as? String, !name.isEmpty { window.title = name }
            replyHandler(true, nil)
        case "openPanel":
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.openPanel() }
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
}

/// ファイル / フォルダのドロップを受けて、WebView 自身の遷移ではなくアプリ側で開く。
final class DropWebView: WKWebView {
    var onDrop: (([URL]) -> Void)?

    /// 開けるもの: フォルダ、または対応拡張子のファイル
    static func accepts(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue || Workspace.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// nil: ファイルのドラッグではない（WebView の既定動作に任せる）
    private func operation(_ info: NSDraggingInfo) -> NSDragOperation? {
        let urls = fileURLs(info)
        if urls.isEmpty { return nil }
        return urls.contains(where: Self.accepts) ? .copy : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(sender) ?? super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(sender) ?? super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let op = operation(sender) else { return super.prepareForDragOperation(sender) }
        return !op.isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        if urls.isEmpty { return super.performDragOperation(sender) }
        let accepted = urls.filter(Self.accepts)
        guard !accepted.isEmpty else { return false }
        DispatchQueue.main.async { [onDrop] in onDrop?(accepted) }
        return true
    }
}
