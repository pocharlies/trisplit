// Trisplit entry point: CLI self-checks, otherwise the menu bar app.
import AppKit
import ApplicationServices
import ServiceManagement

let args = CommandLine.arguments

if let i = args.firstIndex(of: "--login-item") {
    // Login item CLI: on|off|status via SMAppService.mainApp, no UI.
    let svc = SMAppService.mainApp
    func statusName(_ s: SMAppService.Status) -> String {
        switch s {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown(\(s.rawValue))"
        }
    }
    let mode = i + 1 < args.count ? args[i + 1] : ""
    do {
        switch mode {
        case "on": try svc.register()
        case "off": try svc.unregister()
        case "status": break
        default:
            FileHandle.standardError.write("usage: Trisplit --login-item on|off|status\n".data(using: .utf8)!)
            exit(2)
        }
    } catch {
        FileHandle.standardError.write("login item \(mode) failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        print("login item: \(statusName(svc.status))")
        exit(1)
    }
    print("login item: \(statusName(svc.status))")
    exit(0)
}

if args.contains("--selftest") {
    print(engineSmokeReport())
    exit(0)
}

if args.contains("--selftest-live") {
    // Hermetic: without TRISPLIT_STATE, load a scratch copy so the real state is never written.
    var env = ProcessInfo.processInfo.environment
    if (env["TRISPLIT_STATE"] ?? "").isEmpty {
        let home = NSHomeDirectory()
        let dir = NSTemporaryDirectory() + "trisplit-live-\(getpid())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let copy = dir + "/trisplit.json"
        for src in [defaultStatePath(home: home), legacyStatePath(home: home)]
        where FileManager.default.fileExists(atPath: src) {
            try? FileManager.default.copyItem(atPath: src, toPath: copy)
            break
        }
        env["TRISPLIT_STATE"] = copy
    }
    _ = NSApplication.shared
    let engine = Engine(env: env)
    print(engineSmokeReport())
    print("state: \(engine.statePath) configs=\(engine.state.configs.count) active=\(engine.state.active)")
    print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
    print("NSScreens: \(NSScreen.screens.count)")
    let hsV1 = hammerspoonV1Active()
    print("hammerspoon v1 active: \(hsV1) force: \(forceHotkeys())")
    if shouldSkipHotkeys() {
        print("hotkeys skipped (Hammerspoon v1)")
    } else {
        let hk = Hotkeys()
        if hk.installStatus != noErr { print("InstallEventHandler OSStatus \(hk.installStatus)") }
        registerTrisplitHotkeys(hk, engine: engine) {}
        print("hotkeys registered: \(hk.registered)/21")
        for f in hk.failed { print("  hotkey failed: \(f)") }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
