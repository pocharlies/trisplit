// Detects whether ~/.hammerspoon/init.lua is the trisplit v1 (Hammerspoon) config.
import Foundation

/// True when a directory looks like the trisplit repo root.
func isTrisplitRepo(_ dir: String) -> Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: dir + "/build.sh") && fm.fileExists(atPath: dir + "/panel.html")
        && fm.fileExists(atPath: dir + "/app/Core")
}

/// v1 config = init.lua is a symlink whose realpath lies inside the trisplit repo,
/// OR its text binds hotkeys (`hs.hotkey.bind`) and mentions "trisplit".
/// A plain migration stub that merely mentions trisplit does not count.
func isTrisplitV1Config(initLua: String) -> Bool {
    let fm = FileManager.default
    guard fm.fileExists(atPath: initLua) else { return false }
    let isLink = (try? fm.destinationOfSymbolicLink(atPath: initLua)) != nil
    let real = URL(fileURLWithPath: initLua).resolvingSymlinksInPath().path
    if isLink {
        var dir = (real as NSString).deletingLastPathComponent
        while dir != "/" && !dir.isEmpty {
            if isTrisplitRepo(dir) { return true }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }
    let text = ((try? String(contentsOfFile: real, encoding: .utf8)) ?? "").lowercased()
    return text.contains("hs.hotkey.bind") && text.contains("trisplit")
}
