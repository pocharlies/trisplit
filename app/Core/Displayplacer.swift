// displayplacer integration: parse `displayplacer list`, compute the arrangement args.
import Foundation

let DISPLAYPLACER = "/opt/homebrew/bin/displayplacer"
let ERR_NO_DISPLAYPLACER = "displayplacer no instalado"
let ERR_NO_BLOCKS = "displayplacer no devolvió pantallas"

struct DisplayBlock: Equatable {
    var id: String
    var w: Int?
    var h: Int?
    var hertz: String?
    var x: Int?
    var y: Int?
    var main = false
    var rot: String?
    var scaling: String?
    var depth: String?
}

/// Anchored scanner over unicode scalars; character classes are ASCII like Lua's.
private struct Scan {
    let s: [Unicode.Scalar]
    var i = 0

    init(_ line: Substring.UnicodeScalarView) { s = Array(line) }

    mutating func lit(_ p: String) -> Bool {
        let ps = Array(p.unicodeScalars)
        guard i + ps.count <= s.count, Array(s[i..<(i + ps.count)]) == ps else { return false }
        i += ps.count
        return true
    }

    /// One or more scalars matching `pred` (greedy).
    mutating func run(_ pred: (Unicode.Scalar) -> Bool) -> String? {
        let start = i
        while i < s.count, pred(s[i]) { i += 1 }
        guard i > start else { return nil }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: s[start..<i])
        return String(out)
    }

    /// `%-?%d+`
    mutating func signedInt() -> Int? {
        let save = i
        let neg = lit("-")
        guard let d = run(isDigit), let v = Int(d) else { i = save; return nil }
        return neg ? -v : v
    }
}

private func isDigit(_ c: Unicode.Scalar) -> Bool { c.value >= 48 && c.value <= 57 }
private func isAlpha(_ c: Unicode.Scalar) -> Bool {
    (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122)
}
private func isAlnumDash(_ c: Unicode.Scalar) -> Bool { isDigit(c) || isAlpha(c) || c == "-" }

private func prefixed(_ line: Substring.UnicodeScalarView, _ p: String) -> Scan? {
    var sc = Scan(line)
    return sc.lit(p) ? sc : nil
}

/// Lua parseDisplayplacer(): lines are split on "\n" bytes, empty lines skipped.
func parseDisplayplacer(_ text: String) -> [DisplayBlock] {
    var blocks: [DisplayBlock] = []
    for line in text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: true) {
        if var sc = prefixed(line, "Persistent screen id: "), let id = sc.run(isAlnumDash) {
            blocks.append(DisplayBlock(id: id))
        }
        guard !blocks.isEmpty else { continue }
        var cur = blocks.removeLast()
        if var sc = prefixed(line, "Resolution: "), let w = sc.run(isDigit), sc.lit("x"),
           let h = sc.run(isDigit), let wi = Int(w), let hi = Int(h) {
            cur.w = wi
            cur.h = hi
        }
        if var sc = prefixed(line, "Hertz: "), let hz = sc.run({ isDigit($0) || $0 == "." }) {
            cur.hertz = hz
        }
        if var sc = prefixed(line, "Origin: ("), let ox = sc.signedInt(), sc.lit(","),
           let oy = sc.signedInt(), sc.lit(")") {
            cur.x = ox
            cur.y = oy
        }
        if String(String.UnicodeScalarView(line)).contains("main display") { cur.main = true }
        if var sc = prefixed(line, "Rotation: "), let r = sc.run(isDigit) { cur.rot = r }
        if var sc = prefixed(line, "Scaling: "), let v = sc.run(isAlpha) { cur.scaling = v }
        if var sc = prefixed(line, "Color Depth: "), let d = sc.run(isDigit) { cur.depth = d }
        blocks.append(cur)
    }
    return blocks
}

private func fl(_ d: Double) -> Int { floorInt(d) ?? 0 }

/// Lua currentOffsets(): floored full-frame origins (top-left global), last same name wins.
func currentOffsets(screens: [(name: String, full: Rect)]) -> [String: Offset] {
    var out: [String: Offset] = [:]
    for s in screens { out[s.name] = Offset(dx: Double(fl(s.full.x)), dy: Double(fl(s.full.y))) }
    return out
}

func displayplacerArg(_ b: DisplayBlock, ox: Int, oy: Int) -> String {
    "id:\(b.id) res:\(b.w ?? 0)x\(b.h ?? 0) hz:\(b.hertz ?? "")"
        + " color_depth:\(b.depth ?? "8") enabled:true scaling:\(b.scaling ?? "off")"
        + " origin:(\(ox),\(oy)) degree:\(b.rot ?? "0")"
}

/// Lua applyArrangement() minus the exec: returns the displayplacer argv (without the binary)
/// or the Spanish error message. `screens` carry full frames in top-left global coordinates.
func arrangementArgs(screens: [(name: String, full: Rect)], offsets: [String: Offset]?,
                     blocks: [DisplayBlock]) -> Result<[String], ArrangeError> {
    guard !blocks.isEmpty else { return .failure(ArrangeError(ERR_NO_BLOCKS)) }
    struct R { var name: String; var x, y, w, h: Int }
    var rects: [R] = screens.map { s in
        let off = offsets?[s.name]
        return R(name: s.name,
                 x: off.map { fl($0.dx) } ?? fl(s.full.x),
                 y: off.map { fl($0.dy) } ?? fl(s.full.y),
                 w: fl(s.full.w), h: fl(s.full.h))
    }
    var newMain = rects.first { $0.x == 0 && $0.y == 0 }
    if newMain == nil {
        rects = rects.enumerated().sorted { a, b in
            if a.element.x != b.element.x { return a.element.x < b.element.x }
            if a.element.y != b.element.y { return a.element.y < b.element.y }
            return a.offset < b.offset
        }.map { $0.element }
        newMain = rects.first
    }
    guard let nm = newMain else { return .failure(ArrangeError(ERR_NO_BLOCKS)) }
    var args: [String] = []
    for r in rects {
        var curX: Int?, curY: Int?
        for s in screens where s.name == r.name {
            curX = fl(s.full.x)
            curY = fl(s.full.y)
        }
        let match = blocks.first {
            $0.w == r.w && $0.h == r.h && $0.x == curX && $0.y == curY && $0.hertz != nil
        }
        guard let m = match else {
            return .failure(ArrangeError("no se encontró \(r.name) en displayplacer"))
        }
        args.append(displayplacerArg(m, ox: r.x - nm.x, oy: r.y - nm.y))
    }
    return .success(args)
}

struct ArrangeError: Error, Equatable {
    var message: String
    init(_ m: String) { message = m }
}
