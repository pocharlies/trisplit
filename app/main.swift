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
  var stateTimer: Timer?
  var lastStateDate: Date?
  var lastStateJSON = ""
  let stateFile = ("~/.hammerspoon/.trisplit_panel_state.json" as NSString).expandingTildeInPath

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

    stateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
      self.checkStateFile()
    }
  }

  func checkStateFile() {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: stateFile),
          let mtime = attrs[.modificationDate] as? Date else { return }
    if lastStateDate == mtime { return }
    lastStateDate = mtime
    guard let str = try? String(contentsOfFile: stateFile, encoding: .utf8),
          str.hasPrefix("{"), str != lastStateJSON else { return }
    lastStateJSON = str
    webview.evaluateJavaScript("trisplitSetState(\(str))")
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
      guard let out, let lo = out.firstIndex(of: "{"), let hi = out.lastIndex(of: "}") else { return }
      let json = String(out[lo...hi])
      if json == self.lastStateJSON { return }
      self.lastStateJSON = json
      if let attrs = try? FileManager.default.attributesOfItem(atPath: self.stateFile) {
        self.lastStateDate = attrs[.modificationDate] as? Date
      }
      self.webview.evaluateJavaScript("trisplitSetState(\(json))")
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
