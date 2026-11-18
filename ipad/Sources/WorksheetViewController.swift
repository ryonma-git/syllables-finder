import UIKit
import WebKit

/// Only the bundled main document owns the bridge. Printed markup has a separate, script-free view.
final class WorksheetViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private var worksheet: WKWebView?
    private var printView: WKWebView?
    private var printContentRule: WKContentRuleList?
    private var export: (action: String, filename: String)?
    private let entry = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        guard let entry else { showError("教材画面がアプリに含まれていません。"); return }
        // Web assets stay local. Only the optional API action in the editor can reach OpenAI.
        let blockRemote = #"{"trigger":{"url-filter":"^http"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ws"},"action":{"type":"block"}}"#
        let allowAPI = #"{"trigger":{"url-filter":"^https://api\\.openai\\.com/v1/responses$"},"action":{"type":"ignore-previous-rules"}}"#
        Task {
            let store = WKContentRuleListStore.default()!
            do {
                printContentRule = try await store.compileContentRuleList(forIdentifier: "WorksheetPrint",
                                                                          encodedContentRuleList: "[\(blockRemote)]")
                let editorRule = try await store.compileContentRuleList(forIdentifier: "WorksheetEditor",
                                                                        encodedContentRuleList: "[\(blockRemote),\(allowAPI)]")
                guard let editorRule, printContentRule != nil else { throw URLError(.cannotLoadFromNetwork) }
                loadEditor(at: entry, rule: editorRule)
            } catch {
                showError("教材画面を準備できませんでした。\(error.localizedDescription)")
            }
        }
    }

    private func loadEditor(at entry: URL, rule: WKContentRuleList) {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(rule)
        configuration.userContentController.add(WorksheetBridge(self), name: "worksheet")
        let web = WKWebView(frame: view.bounds, configuration: configuration)
        worksheet = web
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.navigationDelegate = self
        view.addSubview(web)
        web.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let mainFrame = navigationAction.targetFrame?.isMainFrame == true
        let bundled = webView === worksheet && url?.standardizedFileURL == entry?.standardizedFileURL
        let rendering = webView === printView && url?.absoluteString == "about:blank"
        decisionHandler(mainFrame && (bundled || rendering) ? .allow : .cancel)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "worksheet", message.webView === worksheet,
              message.frameInfo.isMainFrame, let origin = message.frameInfo.request.url, let entry,
              origin.standardizedFileURL == entry.standardizedFileURL,
              export == nil, presentedViewController == nil,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        let filename = body["filename"] as? String ?? "歌唱練習シート"
        switch action {
        case "print", "sharePDF":
            guard let html = body["html"] as? String, !html.isEmpty, let printContentRule else { return }
            export = (action, filename)
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.userContentController.add(printContentRule)
            let web = WKWebView(frame: view.bounds, configuration: configuration)
            printView = web
            web.navigationDelegate = self
            web.isUserInteractionEnabled = false
            view.insertSubview(web, at: 0)
            web.loadHTMLString(html, baseURL: nil)
        case "shareText":
            guard let content = body["text"] as? String else { return }
            share(Data(content.utf8), filename: filename, extension: "json")
        default:
            return
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === printView, let export else { return }
        let renderer = WorksheetPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let pages = renderer.numberOfPages
        guard pages > 0 else { endExport(); showError("印刷するページがありません。"); return }
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        let pdf = UIGraphicsPDFRenderer(bounds: renderer.paperRect).pdfData { context in
            for page in 0..<pages {
                context.beginPage()
                renderer.drawPage(at: page, in: renderer.paperRect)
            }
        }
        endExport()
        if export.action == "print" {
            let printer = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = export.filename
            printer.printInfo = info
            printer.printingItem = pdf
            printer.present(from: shareAnchor, in: view, animated: true) { [weak self] _, _, error in
                if let error { self?.showError(error.localizedDescription) }
            }
        } else {
            share(pdf, filename: export.filename, extension: "pdf")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === printView { endExport() }
        if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    private func endExport() {
        printView?.removeFromSuperview()
        printView = nil
        export = nil
    }

    private var shareAnchor: CGRect {
        CGRect(x: view.bounds.midX, y: view.bounds.maxY - view.safeAreaInsets.bottom - 40, width: 1, height: 1)
    }

    private func share(_ data: Data, filename: String, extension ext: String) {
        let component = (filename as NSString).lastPathComponent as NSString
        let base = component.pathExtension.lowercased() == ext ? component.deletingPathExtension : component as String
        let invalid = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        var clean = base.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        while clean.utf8.count > 230 { clean.removeLast() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(clean.isEmpty ? "歌唱練習シート" : clean).appendingPathExtension(ext)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = shareAnchor
            sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
            present(sheet, animated: true)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            showError("教材を書き出せませんでした。\(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "歌唱練習シート", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "閉じる", style: .default))
        present(alert, animated: true)
    }
}

/// WKUserContentController retains its handler for the lifetime of the web view.
private final class WorksheetBridge: NSObject, WKScriptMessageHandler {
    private weak var controller: WorksheetViewController?
    init(_ controller: WorksheetViewController) { self.controller = controller }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        controller?.userContentController(userContentController, didReceive: message)
    }
}

/// A4 point sizes are shared by the exported file and the native print preview.
private final class WorksheetPageRenderer: UIPrintPageRenderer {
    override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 595.28, height: 841.89) }
    override var printableRect: CGRect { paperRect.insetBy(dx: 28, dy: 28) }
}
