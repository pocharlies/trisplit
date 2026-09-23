// Menu bar item: left click opens the panel, right click shows the menu.
import AppKit
import ApplicationServices
import ServiceManagement

let TRISPLIT_LOG_PATH = NSHomeDirectory() + "/Library/Logs/Trisplit/trisplit.log"

final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let loginItem = NSMenuItem(title: "Abrir al iniciar sesión", action: nil, keyEquivalent: "")
    private let axItem = NSMenuItem(title: "⚠︎ Conceder permiso de Accesibilidad…", action: nil, keyEquivalent: "")
    private let axSep = NSMenuItem.separator()
    private let configHeader = NSMenuItem(title: "Config: —", action: nil, keyEquivalent: "")
    private let hotkeysItem = NSMenuItem(title: "Tomar atajos de Hammerspoon", action: nil, keyEquivalent: "")
    private let engine: Engine
    private let openPanel: () -> Void
    private let takeHotkeys: () -> Void
    private let hotkeysActive: () -> Bool

    init(engine: Engine, openPanel: @escaping () -> Void,
         takeHotkeys: @escaping () -> Void = {}, hotkeysActive: @escaping () -> Bool = { true }) {
        self.engine = engine
        self.openPanel = openPanel
        self.takeHotkeys = takeHotkeys
        self.hotkeysActive = hotkeysActive
        super.init()
        if let button = item.button {
            if let url = Bundle.main.url(forResource: "icon", withExtension: "png"), let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 22, height: 12)
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "▥"
            }
            button.toolTip = "Trisplit"
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        buildMenu()
    }

    private func add(_ title: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = []) {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.keyEquivalentModifierMask = mods
        mi.target = self
        menu.addItem(mi)
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        axItem.action = #selector(openAXSettings)
        axItem.target = self
        menu.addItem(axItem)
        menu.addItem(axSep)
        configHeader.isEnabled = false
        menu.addItem(configHeader)
        add("Abrir Trisplit…", #selector(panel), "p", [.command, .option])
        add("Aplicar configuración", #selector(apply), "0", [.command, .option])
        add("Siguiente configuración", #selector(next), "0", [.command, .option, .shift])
        menu.addItem(.separator())
        hotkeysItem.action = #selector(takeHK)
        hotkeysItem.target = self
        menu.addItem(hotkeysItem)
        loginItem.action = #selector(toggleLogin)
        loginItem.target = self
        menu.addItem(loginItem)
        add("Mostrar registro", #selector(openLog))
        menu.addItem(.separator())
        add("Salir", #selector(quit), "q", [.command])
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let trusted = AXIsProcessTrusted()
        axItem.isHidden = trusted
        axSep.isHidden = trusted
        configHeader.title = "Config: \(engine.state.activeConfig?.name ?? "—")"
        hotkeysItem.isHidden = hotkeysActive()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let ev = NSApp.currentEvent
        if ev?.type == .rightMouseUp || ev?.modifierFlags.contains(.control) == true {
            item.menu = menu
            item.button?.performClick(nil)  // pops the menu
            item.menu = nil                  // restore left-click action
        } else {
            openPanel()
        }
    }

    @objc private func panel() { openPanel() }
    @objc private func apply() { engine.applyConfig() }
    @objc private func next() { engine.cycleConfig() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func takeHK() { takeHotkeys() }

    @objc private func openAXSettings() {
        if let u = URL(string: AX_SETTINGS_URL) { NSWorkspace.shared.open(u) }
    }

    @objc private func openLog() {
        let url = URL(fileURLWithPath: TRISPLIT_LOG_PATH)
        if !FileManager.default.fileExists(atPath: url.path) { engine.log("log abierto") }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled {
                try svc.unregister()
                engine.log("login item desactivado")
            } else {
                try svc.register()
                engine.log("login item activado (\(svc.status.rawValue))")
            }
        } catch {
            engine.log("login item falló: \(error.localizedDescription)")
        }
    }
}
