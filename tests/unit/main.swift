// Entry point for the Core unit tests (plain swiftc, no XCTest).
import Foundation

geometryTests()
stateTests()
slotsScreensTests()
matchTests()
displayplacerTests()
panelStateTests()
coexistenceTests()

try? FileManager.default.removeItem(atPath: tmpRoot)
print("unit: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
