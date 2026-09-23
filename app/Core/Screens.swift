// Screen model shared by the AppKit layer and the tests. All rects are top-left global.
import Foundation

struct ScreenInfo: Equatable {
    var name: String
    var full: Rect
    var visible: Rect
    var isMain: Bool
}

/// Lua sortedScreens(): by x, then y (stable).
func sortScreens(_ screens: [ScreenInfo]) -> [ScreenInfo] {
    screens.enumerated().sorted { a, b in
        if a.element.full.x != b.element.full.x { return a.element.full.x < b.element.full.x }
        if a.element.full.y != b.element.full.y { return a.element.full.y < b.element.full.y }
        return a.offset < b.offset
    }.map { $0.element }
}

/// Lua screenByName(): first screen with that name.
func screenNamed(_ name: String, in screens: [ScreenInfo]) -> ScreenInfo? {
    screens.first { $0.name == name }
}

/// Lua primaryScreen(): full origin at (0,0), else the main screen.
func primaryScreen(_ screens: [ScreenInfo]) -> String? {
    if let s = screens.first(where: { $0.full.x == 0 && $0.full.y == 0 }) { return s.name }
    return (screens.first { $0.isMain } ?? screens.first)?.name
}
