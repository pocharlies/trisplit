// Global hotkeys via Carbon RegisterEventHotKey. Handlers run on main.
import Carbon
import AppKit

final class Hotkeys {
    struct Binding {
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
        let action: () -> Void
    }

    private var bindings: [UInt32: Binding] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private(set) var registered = 0
    private(set) var failed: [String] = []
    private(set) var installStatus: OSStatus = noErr

    static let signature: OSType = 0x5452_5350  // 'TRSP'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let ref = Unmanaged.passUnretained(self).toOpaque()
        installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, user in
            guard let event, let user else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard st == noErr, id.signature == Hotkeys.signature else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<Hotkeys>.fromOpaque(user).takeUnretainedValue()
            me.bindings[id.id]?.action()
            return noErr
        }, 1, &spec, ref, &handler)
        if installStatus != noErr { NSLog("trisplit: InstallEventHandler falló (OSStatus %d)", installStatus) }
    }

    /// Returns false (and records the label) if RegisterEventHotKey fails. Note: Carbon does NOT fail
    /// when another app (e.g. Hammerspoon) holds the same combo; both fire. See hammerspoonV1Active().
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, label: String, action: @escaping () -> Void) -> Bool {
        let id = UInt32(bindings.count + 1)
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Hotkeys.signature, id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        guard st == noErr, let ref else {
            failed.append("\(label) (OSStatus \(st))")
            return false
        }
        bindings[id] = Binding(keyCode: keyCode, modifiers: modifiers, label: label, action: action)
        refs.append(ref)
        registered += 1
        return true
    }

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

let HK_CMD_ALT = UInt32(cmdKey | optionKey)
let HK_CMD_ALT_SHIFT = UInt32(cmdKey | optionKey | shiftKey)
/// kVK_ANSI_1..9 are not contiguous.
let HK_DIGITS: [UInt32] = [
    UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5),
    UInt32(kVK_ANSI_6), UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
]

/// The 21 v1 bindings.
func registerTrisplitHotkeys(_ hk: Hotkeys, engine: Engine, openPanel: @escaping () -> Void) {
    hk.register(keyCode: UInt32(kVK_ANSI_0), modifiers: HK_CMD_ALT, label: "⌘⌥0") { engine.applyConfig() }
    hk.register(keyCode: UInt32(kVK_ANSI_0), modifiers: HK_CMD_ALT_SHIFT, label: "⌘⌥⇧0") { engine.cycleConfig() }
    hk.register(keyCode: UInt32(kVK_ANSI_P), modifiers: HK_CMD_ALT, label: "⌘⌥P", action: openPanel)
    for (i, k) in HK_DIGITS.enumerated() {
        let n = i + 1
        hk.register(keyCode: k, modifiers: HK_CMD_ALT, label: "⌘⌥\(n)") { engine.moveFrontToSlot(n) }
        hk.register(keyCode: k, modifiers: HK_CMD_ALT_SHIFT, label: "⌘⌥⇧\(n)") { engine.focusSlot(n) }
    }
}

let HAMMERSPOON_BUNDLE_ID = "org.hammerspoon.Hammerspoon"
let HUD_HS_ACTIVE = "Hammerspoon v1 activo: atajos desactivados"

/// TRISPLIT_FORCE_HOTKEYS=1 bypasses the Hammerspoon coexistence gate.
func forceHotkeys(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    env["TRISPLIT_FORCE_HOTKEYS"] == "1"
}

/// True when Hammerspoon is running AND ~/.hammerspoon/init.lua is the trisplit v1 config
/// (see isTrisplitV1Config). Both would fire on the same combos.
func hammerspoonV1Active(home: String = NSHomeDirectory()) -> Bool {
    guard !NSRunningApplication.runningApplications(withBundleIdentifier: HAMMERSPOON_BUNDLE_ID).isEmpty else { return false }
    return isTrisplitV1Config(initLua: home + "/.hammerspoon/init.lua")
}

/// Hotkey decision shared by the app and --selftest-live.
func shouldSkipHotkeys() -> Bool { !forceHotkeys() && hammerspoonV1Active() }
