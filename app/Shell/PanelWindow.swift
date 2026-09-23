// Reusable panel window: WKWebView on Resources/panel.html, bridged to the engine.
import AppKit
import WebKit

/// Esc closes the panel.
final class PanelNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Breaks the WKUserContentController -> handler retain cycle.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}

final class PanelController: NSObject, WKScriptMessageHandler {
    /// Must match `webkit.messageHandlers.<name>` in panel.html.
    static let handlerName = "trisplit"

    private let engine: Engine
    private var window: PanelNSWindow?
    private var webView: WKWebView?
    private var saveItem: DispatchWorkItem?
    private var pendingSave: String?
    private var escMonitor: Any?

    init(engine: Engine) {
        self.engine = engine
        super.init()
    }

    private func build() -> PanelNSWindow {
        let w = PanelNSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Trisplit"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 820, height: 520)
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(WeakScriptHandler(self), name: PanelController.handlerName)
        let wv = WKWebView(frame: w.contentLayoutRect, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        w.contentView = wv
        if let res = Bundle.main.resourceURL {
            let html = res.appendingPathComponent("panel.html")
            wv.loadFileURL(html, allowingReadAccessTo: res)
        } else {
            engine.log("panel: sin Resources en el bundle")
        }
        window = w
        webView = wv
        // WKWebView swallows Esc, so cancelOperation never fires; catch it while the panel is key.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard ev.keyCode == 53, let w = self?.window, w.isKeyWindow else { return ev }
            self?.hide()
            return nil
        }
        return w
    }

    func show() {
        let w = window ?? build()
        if !w.isVisible { center(w) }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        engine.schedulePush(after: 0)
    }

    func hide() { window?.orderOut(nil) }

    func evaluate(_ js: String) {
        webView?.evaluateJavaScript(js) { [weak self] _, err in
            if let err { self?.engine.log("panel JS falló: \(err.localizedDescription)") }
        }
    }

    /// Center on the screen that holds the mouse.
    private func center(_ w: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { w.center(); return }
        let size = w.frame.size
        w.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2))
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        let body: String
        if let s = message.body as? String {
            body = s
        } else if JSONSerialization.isValidJSONObject(message.body),
                  let d = try? JSONSerialization.data(withJSONObject: message.body),
                  let s = String(data: d, encoding: .utf8) {
            body = s
        } else {
            engine.log("panel: mensaje no JSON")
            return
        }
        // Panel posts "save" on every edit; coalesce like the v1 shim did.
        if JSON.parse(body)?["action"]?.string == "save" {
            pendingSave = body
            saveItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.flushSave() }
            saveItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
            return
        }
        // Flush a pending save first so apply/close see the latest configs.
        flushSave()
        engine.handlePanel(body)
    }

    deinit {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
    }

    private func flushSave() {
        saveItem?.cancel()
        saveItem = nil
        guard let b = pendingSave else { return }
        pendingSave = nil
        engine.handlePanel(b)
    }
}
