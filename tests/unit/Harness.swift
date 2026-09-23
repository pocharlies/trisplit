// Tiny assert harness (no XCTest on Command Line Tools).
import Foundation

var passed = 0
var failed = 0
var currentCase = ""

func test(_ name: String, _ body: () throws -> Void) {
    currentCase = name
    do { try body() } catch { fail("threw \(error)") }
}

func fail(_ msg: String, file: String = #fileID, line: Int = #line) {
    failed += 1
    print("FAIL [\(currentCase)] \(file):\(line) \(msg)")
}

func check(_ cond: Bool, _ msg: @autoclosure () -> String = "", file: String = #fileID, line: Int = #line) {
    if cond { passed += 1 } else { fail(msg(), file: file, line: line) }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #fileID, line: Int = #line) {
    if a == b { passed += 1 } else { fail("\(msg) expected \(b), got \(a)", file: file, line: line) }
}

func near(_ a: Double, _ b: Double, _ msg: String = "", eps: Double = 1e-9,
          file: String = #fileID, line: Int = #line) {
    if abs(a - b) <= eps { passed += 1 } else { fail("\(msg) expected \(b), got \(a)", file: file, line: line) }
}

/// Fresh temp dir per test run (never the real state file).
let tmpRoot: String = {
    let p = NSTemporaryDirectory() + "trisplit-unit-\(ProcessInfo.processInfo.processIdentifier)"
    try? FileManager.default.removeItem(atPath: p)
    try! FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
    return p
}()

func tmpPath(_ name: String) -> String { tmpRoot + "/" + name }

func sha256(_ path: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
    p.arguments = ["-a", "256", path]
    let out = Pipe()
    p.standardOutput = out
    try? p.run()
    p.waitUntilExit()
    let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return String(s.split(separator: " ").first ?? "")
}

/// Repo root = two levels above this source file's directory (tests/unit/..).
let repoRoot: String = {
    if let r = ProcessInfo.processInfo.environment["TRISPLIT_REPO"], !r.isEmpty { return r }
    return FileManager.default.currentDirectoryPath
}()

func fixture(_ name: String) -> String { repoRoot + "/tests/fixtures/" + name }
