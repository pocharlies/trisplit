// Minimal JSON value used for lenient decoding (files written by Lua may carry `[]`
// where an object is expected, floats where ints are expected, etc.).
import Foundation

enum JSON: Decodable, Equatable {
    case null
    case bool(Bool)
    case num(Double)
    case str(String)
    case arr([JSON])
    case obj([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        // Numbers first: some decoders accept 0/1 as Bool; none accept true/false as Double.
        if let d = try? c.decode(Double.self) { self = .num(d); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let s = try? c.decode(String.self) { self = .str(s); return }
        if let a = try? c.decode([JSON].self) { self = .arr(a); return }
        if let o = try? c.decode([String: JSON].self) { self = .obj(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    static func parse(_ data: Data) -> JSON? {
        try? JSONDecoder().decode(JSON.self, from: data)
    }

    static func parse(_ text: String) -> JSON? {
        parse(Data(text.utf8))
    }

    var string: String? { if case .str(let s) = self { return s }; return nil }
    var number: Double? { if case .num(let d) = self { return d }; return nil }
    var int: Int? { number.flatMap(floorInt) }
    var object: [String: JSON]? { if case .obj(let o) = self { return o }; return nil }
    var array: [JSON]? { if case .arr(let a) = self { return a }; return nil }
    subscript(key: String) -> JSON? { object?[key] }
}

func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try e.encode(value)
}

func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try encodeJSON(value), as: UTF8.self)
}
