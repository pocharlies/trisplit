// App-name aliasing and matching (no AppKit).
import Foundation

let ALIASES: [String: String] = ["Code": "Visual Studio Code", "Visual Studio Code": "Code"]

/// [app] plus its alias, if any (Lua namesFor).
func namesFor(_ app: String) -> [String] {
    var out = [app]
    if let a = ALIASES[app] { out.append(a) }
    return out
}

/// Drops Unicode format characters (e.g. U+200E in "‎WhatsApp") and trims whitespace.
func stripFormat(_ s: String) -> String {
    let scalars = s.unicodeScalars.filter { $0.properties.generalCategory != .format }
    return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
}

func normalizedAppName(_ s: String) -> String {
    stripFormat(s).lowercased()
}

/// Exact name match for each name first (in order), then a normalized match.
func bestMatch<T>(names: [String], candidates: [(name: String, value: T)]) -> T? {
    for n in names {
        if let c = candidates.first(where: { $0.name == n }) { return c.value }
    }
    for n in names {
        let nn = normalizedAppName(n)
        if nn.isEmpty { continue }
        if let c = candidates.first(where: { normalizedAppName($0.name) == nn }) { return c.value }
    }
    return nil
}

/// Lua string.lower (ASCII only) for the apps sort.
func asciiLower(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.map { sc in
        (sc.value >= 65 && sc.value <= 90) ? Unicode.Scalar(sc.value + 32)! : sc
    }))
}
