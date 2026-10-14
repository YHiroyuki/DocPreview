import Foundation
import UniformTypeIdentifiers
import WebKit

/// `docpreview://app/...` を処理する。UI とドキュメントを同一オリジンで配信するため、
/// 親ページから iframe 内の DOM を操作できる（選択範囲の取得やハイライトに必要）。
///
/// - `/ui/*`   : アプリ UI（バンドルされたリソース）
/// - `/doc/*`  : ワークスペース配下のファイル。Markdown は HTML に整形して返す
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    var workspace: Workspace?
    private let uiRoot: URL

    init(uiRoot: URL) {
        self.uiRoot = uiRoot
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return fail(task) }
        let path = url.path.removingPercentEncoding ?? url.path

        if path.hasPrefix("/ui/") {
            serveFile(task, url: url, file: uiRoot.appendingPathComponent(String(path.dropFirst(4))), under: uiRoot)
        } else if path.hasPrefix("/doc/"), let ws = workspace {
            let rel = String(path.dropFirst(5))
            let file = ws.root.appendingPathComponent(rel).standardizedFileURL
            if ["md", "markdown"].contains(file.pathExtension.lowercased()),
               url.query != "raw" {
                serveMarkdown(task, url: url, file: file, under: ws.root)
            } else {
                serveFile(task, url: url, file: file, under: ws.root)
            }
        } else {
            respond(task, url: url, status: 404, mime: "text/plain", data: Data("not found".utf8))
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func inside(_ file: URL, _ root: URL) -> Bool {
        let base = root.standardizedFileURL.path
        let p = file.standardizedFileURL.resolvingSymlinksInPath().path
        let r = URL(fileURLWithPath: base).resolvingSymlinksInPath().path
        return p == r || p.hasPrefix(r + "/")
    }

    private func serveFile(_ task: WKURLSchemeTask, url: URL, file: URL, under root: URL) {
        guard inside(file, root), let data = try? Data(contentsOf: file) else {
            return respond(task, url: url, status: 404, mime: "text/plain", data: Data("not found".utf8))
        }
        respond(task, url: url, status: 200, mime: mimeType(for: file), data: data)
    }

    private func serveMarkdown(_ task: WKURLSchemeTask, url: URL, file: URL, under root: URL) {
        guard inside(file, root), let source = try? String(contentsOf: file, encoding: .utf8) else {
            return respond(task, url: url, status: 404, mime: "text/plain", data: Data("not found".utf8))
        }
        // JSON 文字列として安全に埋め込む（</script> 対策に "<" をエスケープ）
        let json = (try? JSONSerialization.data(withJSONObject: [source], options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        let safe = json.replacingOccurrences(of: "<", with: "\\u003c")
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <link rel="stylesheet" href="docpreview://app/ui/markdown-base.css">
        </head><body><article class="markdown-body" id="content"></article>
        <script>window.__SOURCE__ = \(safe)[0];</script>
        <script src="docpreview://app/ui/markdown-view.js"></script>
        </body></html>
        """
        respond(task, url: url, status: 200, mime: "text/html", data: Data(html.utf8))
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, data: Data) {
        let headers = [
            "Content-Type": mime.hasPrefix("text/") || mime.contains("javascript") || mime.contains("json")
                ? "\(mime); charset=utf-8" : mime,
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-store",
        ]
        let res = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(res)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(URLError(.badURL))
    }

    private func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js", "mjs": return "text/javascript"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "md", "markdown", "txt": return "text/plain"
        default:
            return UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
