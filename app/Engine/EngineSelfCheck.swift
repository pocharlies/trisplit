// Read-only diagnostic report: never moves windows or writes state.
import AppKit
import ApplicationServices

func engineSmokeReport() -> String {
    var out: [String] = []
    let trusted = AXIsProcessTrusted()
    out.append("AXIsProcessTrusted: \(trusted)")
    let scr = sortScreens(currentScreens())
    out.append("screens: \(scr.count)")
    for s in scr {
        out.append("  \(s.name) main=\(s.isMain) full=\(fmt(s.full)) visible=\(fmt(s.visible))")
    }
    let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    out.append("regular apps: \(regular.count)")
    if trusted {
        for a in regular {
            out.append("  \(a.localizedName ?? "?"): visibleWindows=\(visibleWindows(pid: a.processIdentifier).count)")
        }
    } else {
        out.append("  (sin Accesibilidad: ventanas no enumerables)")
    }
    return out.joined(separator: "\n")
}

private func fmt(_ r: Rect) -> String {
    "(\(Int(r.x)),\(Int(r.y)) \(Int(r.w))x\(Int(r.h)))"
}
