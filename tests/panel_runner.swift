// Standalone headless test runner for panel.html (not part of the app).
// Usage: build/panel_runner <panel.html> <tests.js>
// Exit: 0 = summary has " 0 failed" and no JS-EXCEPTION, 1 = failures, 2 = timeout.
import AppKit
import WebKit

setvbuf(stdout, nil, _IOLBF, 0)

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: panel_runner <panel.html> <tests.js>\n".data(using: .utf8)!)
    exit(1)
}
let htmlURL = URL(fileURLWithPath: args[1]).standardizedFileURL
let testsURL = URL(fileURLWithPath: args[2]).standardizedFileURL
guard let testsJS = try? String(contentsOf: testsURL, encoding: .utf8) else {
    FileHandle.standardError.write("cannot read \(testsURL.path)\n".data(using: .utf8)!)
    exit(1)
}

final class Runner: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var sawException = false
    var summary: String?
    var ranTests = false
    let testsJS: String

    init(testsJS: String) { self.testsJS = testsJS }

    func finish() -> Never {
        if let s = summary, s.contains(" 0 failed"), !sawException { exit(0) }
        if summary == nil { print("runner: no summary line received") }
        exit(1)
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "trisplitTest" else { return } // "trisplit" bridge traffic is ignored
        let line = (message.body as? String) ?? "\(message.body)"
        print(line)
        if line.hasPrefix("JS-EXCEPTION:") { sawException = true }
        if line.hasPrefix("panel:") {
            summary = line
            // let any trailing async errors surface before exiting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.finish() }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !ranTests else { return }
        ranTests = true
        webView.evaluateJavaScript(testsJS) { _, error in
            if let error = error as NSError? {
                let msg = (error.userInfo["WKJavaScriptExceptionMessage"] as? String) ?? error.localizedDescription
                let ln = (error.userInfo["WKJavaScriptExceptionLineNumber"] as? Int).map(String.init) ?? "?"
                print("JS-EXCEPTION: \(msg) at \(ln)")
                self.sawException = true
                if self.summary == nil { self.finish() }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("runner: navigation failed: \(error.localizedDescription)"); exit(1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("runner: load failed: \(error.localizedDescription)"); exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let runner = Runner(testsJS: testsJS)
let ucc = WKUserContentController()
ucc.add(runner, name: "trisplit")
ucc.add(runner, name: "trisplitTest")
let hook = """
(function(){
  function report(m){ try { window.webkit.messageHandlers.trisplitTest.postMessage(m); } catch(_){} }
  window.onerror = function(msg, src, line){ report("JS-EXCEPTION: " + msg + " at " + line); };
  window.addEventListener("unhandledrejection", function(ev){
    var r = ev.reason; report("JS-EXCEPTION: " + ((r && r.message) || String(r)) + " at " + ((r && r.line) || "?"));
  });
})();
"""
ucc.addUserScript(WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))

let conf = WKWebViewConfiguration()
conf.userContentController = ucc
let frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
let web = WKWebView(frame: frame, configuration: conf)
web.navigationDelegate = runner
window.contentView = web
window.orderBack(nil)

web.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())

DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    print("runner: timeout after 20s")
    exit(2)
}
app.run()
