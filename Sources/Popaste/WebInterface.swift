import AppKit
import WebKit

/// Only the bundled interface can invoke these local application actions.
final class WebInterface: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let view: WKWebView
    var action: ((String, [String: Any]) -> Void)?
    var state: [String: Any] = [:] { didSet { push() } }
    private var ready = false
    private var openPending: String?
    init(mode: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "native")
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        view.autoresizingMask = [.width, .height]
        let url = Bundle.module.url(forResource: "interface", withExtension: "html")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.fragment = "mode=\(mode)"
        view.loadFileURL(components.url!, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    func attach(to window: NSWindow) {
        let size = window.contentView!.bounds.size
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView); window.setContentSize(size)
        window.isReleasedWhenClosed = false
        view.frame = NSRect(origin: .zero, size: size); window.contentView = view; window.center()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let name = body["action"] as? String else { return }
        if name == "ready" { ready = true; push(); if let destination = openPending { open(destination) } }
        action?(name, body)
    }
    private func push() {
        guard ready, let data = try? JSONSerialization.data(withJSONObject: state, options: [.fragmentsAllowed]), let json = String(data: data, encoding: .utf8) else { return }
        view.evaluateJavaScript("window.nativeState(\(json))", completionHandler: nil)
    }
    func open(_ destination: String = "resume") {
        openPending = ready ? nil : destination
        if ready { call("nativeOpen", destination) }
    }
    func call(_ name: String, _ argument: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: [argument]), let json = String(data: data, encoding: .utf8) else { return }
        view.evaluateJavaScript("window.\(name)(\(json)[0])", completionHandler: nil)
    }
    func toast(_ text: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]), let json = String(data: data, encoding: .utf8) else { return }
        view.evaluateJavaScript("window.nativeToast(\(json)[0])", completionHandler: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true && navigationAction.navigationType == .other ? .allow : .cancel)
    }
}
func interfacePrompts(_ prompts: [Prompt]) -> [[String: Any]] { prompts.map { ["id": $0.id.uuidString, "body": $0.body, "pinned": $0.pinned] } }
func interfaceDark(_ appearance: String = "system") -> Bool { appearance == "dark" || (appearance == "system" && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) }
