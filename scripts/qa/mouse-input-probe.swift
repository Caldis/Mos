import AppKit
import CoreGraphics

struct MouseObservation: Encodable {
    let phase: String
    let number: Int64
}

struct Result: Encodable {
    let source = "quartz"
    let button: Int64
    let pageBefore: Int
    let pageAfter: Int
    let upstream: [MouseObservation]
    let downstream: [MouseObservation]
}

final class Recorder {
    let marker: Int64
    var observations: [MouseObservation] = []

    init(marker: Int64) { self.marker = marker }
}

func fail(_ reason: String) -> Never {
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(1)
}

func windows() -> [[String: Any]] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    return list as? [[String: Any]] ?? []
}

func bounds(of window: [String: Any]) -> CGRect? {
    guard let rect = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: rect as CFDictionary)
}

func page(in window: [String: Any], prefix: String) -> Int? {
    guard let title = window[kCGWindowName as String] as? String, title.hasPrefix(prefix) else { return nil }
    return Int(title.dropFirst(prefix.count).prefix(while: \.isNumber))
}

func observe(at location: CGEventTapLocation, place: CGEventTapPlacement, with recorder: Recorder) -> CFMachPort {
    let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue) |
               CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: location, place: place, options: .listenOnly, eventsOfInterest: mask,
        callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<Recorder>.fromOpaque(context).takeUnretainedValue()
            if event.getIntegerValueField(.eventSourceUserData) == recorder.marker {
                let phase = type == .otherMouseDown ? "down" : "up"
                recorder.observations.append(MouseObservation(phase: phase, number: event.getIntegerValueField(.mouseEventNumber)))
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(recorder).toOpaque()
    ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
        fail("Could not install the listen-only mouse observer")
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return tap
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let button = Int64(arguments[2]), (2...31).contains(button) else {
    fail("Usage: mouse-input-probe <fixture-token> <button-number>")
}
guard #available(macOS 10.15, *),
      CGPreflightPostEventAccess(), CGPreflightListenEventAccess(), CGPreflightScreenCaptureAccess() else {
    fail("The invoking terminal needs existing permission to post and observe input and identify the fixture window")
}
let prefix = "Mos Input QA \(arguments[1]) | "
let normalWindows = windows().filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
let targets = normalWindows.filter { page(in: $0, prefix: prefix) == 3 }
guard targets.count == 1, let target = targets.first,
      let windowID = target[kCGWindowNumber as String] as? Int,
      let processID = target[kCGWindowOwnerPID as String] as? pid_t,
      let browser = NSRunningApplication(processIdentifier: processID),
      ["com.google.Chrome", "com.apple.Safari"].contains(browser.bundleIdentifier),
      let rect = bounds(of: target), rect.width > 250, rect.height > 250 else {
    fail("Expected exactly one visible Chrome or Safari fixture on page 3")
}

if NSWorkspace.shared.frontmostApplication?.processIdentifier != processID {
    _ = browser.activate()
    let deadline = Date(timeIntervalSinceNow: 1.5)
    while NSWorkspace.shared.frontmostApplication?.processIdentifier != processID, Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}
let orderedWindows = windows().filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
let candidates = [rect.midX, rect.minX + 30, rect.maxX - 30].map { CGPoint(x: $0, y: rect.midY) }
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
      let point = candidates.first(where: { point in
          let front = orderedWindows.first { bounds(of: $0)?.contains(point) == true }
          return (front?[kCGWindowNumber as String] as? Int) == windowID
      }) else {
    fail("The fixture must be foreground with an exposed area in the page")
}

// Observe the tagged pair immediately before the session tap and after it.
let marker = Int64(0x51410000) + Int64(getpid())
let eventNumber = Int64(UInt32.random(in: 100_000...2_000_000))
let upstream = Recorder(marker: marker)
let downstream = Recorder(marker: marker)
let entry = observe(at: .cgSessionEventTap, place: .headInsertEventTap, with: upstream)
let exitTap = observe(at: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap, with: downstream)
guard let input = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(mouseEventSource: input, mouseType: .otherMouseDown, mouseCursorPosition: point, mouseButton: .center),
      let up = CGEvent(mouseEventSource: input, mouseType: .otherMouseUp, mouseCursorPosition: point, mouseButton: .center) else {
    fail("Could not construct the native side-button pair")
}
for event in [down, up] {
    event.flags = []
    event.setIntegerValueField(.mouseEventButtonNumber, value: button)
    event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
    event.setIntegerValueField(.eventSourceUserData, value: marker)
}
DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
    down.post(tap: .cghidEventTap)
}
DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
    up.post(tap: .cghidEventTap)
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.25))
CGEvent.tapEnable(tap: entry, enable: false)
CGEvent.tapEnable(tap: exitTap, enable: false)

guard let observedWindow = windows().first(where: { ($0[kCGWindowNumber as String] as? Int) == windowID }),
      let finalPage = page(in: observedWindow, prefix: prefix) else {
    fail("Could not identify the browser fixture after sending the pair")
}
let result = Result(button: button, pageBefore: 3, pageAfter: finalPage, upstream: upstream.observations, downstream: downstream.observations)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
print(String(decoding: try encoder.encode(result), as: UTF8.self))
