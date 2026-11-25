import AppKit

struct ScrollDisplayLayout {
    struct Display: Equatable {
        let id: CGDirectDisplayID
        let hz: Double
    }

    struct Screen {
        let display: Display
        let bounds: CGRect
    }

    private let screens: [Screen]
    private var lastMatch: Screen?

    init(screens: [Screen]) {
        self.screens = screens
    }

    var lastDisplay: Display? { lastMatch?.display }

    mutating func display(at location: CGPoint?) -> Display? {
        if let location, let lastMatch, lastMatch.bounds.contains(location) {
            return lastMatch.display
        }
        let match = location.flatMap { point in screens.first { $0.bounds.contains(point) } }
        lastMatch = match ?? screens.first
        return lastMatch?.display
    }

    static func active() -> ScrollDisplayLayout {
        let screens: [Screen] = NSScreen.screens.compactMap { screen in
            guard let id = screen.frameClockDisplayID,
                  CGDisplayIsActive(id) != 0, CGDisplayIsAsleep(id) == 0 else { return nil }
            let hz: Double
            if let reported = CGDisplayCopyDisplayMode(id)?.refreshRate, reported.isFinite && reported > 0 {
                hz = reported
            } else if #available(macOS 12.0, *), screen.maximumFramesPerSecond > 0 {
                hz = Double(screen.maximumFramesPerSecond)
            } else {
                hz = 60
            }
            // CGEvent.location and CGDisplayBounds use the same global coordinates.
            return Screen(display: Display(id: id, hz: hz), bounds: CGDisplayBounds(id))
        }
        return ScrollDisplayLayout(screens: screens)
    }
}

extension NSScreen {
    var frameClockDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
