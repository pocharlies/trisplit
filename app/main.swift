import Cocoa
import WebKit

let repoDir = ("~/Documents/ClaudecodeTools/trisplit" as NSString).expandingTildeInPath
let hsBin = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/hs")
  ? "/opt/homebrew/bin/hs" : "/usr/local/bin/hs"

func runHS(_ code: String, _ completion: ((String?) -> Void)? = nil) {
  DispatchQueue.global().async {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: hsBin)
    p.arguments = ["-c", code]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { DispatchQueue.main.async { completion?(nil) }; return }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    DispatchQueue.main.async { completion?(text) }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
  var window: NSWindow!
  var webview: WKWebView!
  var saveTimer: Timer?

  func applicationDidFinishLaunching(_ note: Notification) {
    NSApp.setActivationPolicy(.accessory)

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "Trisplit"
    window.isReleasedWhenClosed = false
    window.center()

    let config = WKWebViewConfiguration()
    config.userContentController.add(self, name: "trisplit")
    webview = WKWebView(frame: window.contentLayoutRect, configuration: config)
    webview.autoresizingMask = [.width, .height]
    webview.navigationDelegate = self
    window.contentView = webview

    let html = URL(fileURLWithPath: repoDir + "/panel.html")
    webview.loadFileURL(html, allowingReadAccessTo: URL(fileURLWithPath: repoDir))

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showAndRefresh()
    return true
  }

  func showAndRefresh() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    fetchState()
  }

  func fetchState() {
    runHS("return hs.json.encode(trisplit.panelState())") { out in
      FileHandle.standardError.write("fetchState -> \(String(describing: out?.prefix(80)))\n".data(using: .utf8)!)
      guard let out, out.hasPrefix("{") else { return }
      self.webview.evaluateJavaScript("trisplitSetState(\(out))") { _, _ in
        self.webview.evaluateJavaScript("document.querySelectorAll('#chips .tchip').length + ' chips: ' + Array.from(document.querySelectorAll('#chips .tchip')).slice(0,12).map(c => c.textContent).join(' | ')") { r, _ in
          FileHandle.standardError.write("chips -> \(String(describing: r))\n".data(using: .utf8)!)
        }
      }
    }
  }

  func forward(_ payload: String) {
    let b64 = Data(payload.utf8).base64EncodedString()
    runHS("trisplit.handlePanelB64('\(b64)')")
  }

  func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let str = message.body as? String,
          let data = str.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let action = json["action"] as? String
    else { return }

    switch action {
    case "ready":
      fetchState()
    case "save":
      saveTimer?.invalidate()
      saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
        self.forward(str)
      }
    case "close", "applyAndClose":
      forward(str)
      window.orderOut(nil)
    default:
      forward(str)
    }
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
