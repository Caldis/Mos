import Cocoa
import XCTest
@testable import Mos_Debug

final class EventMonitorTests: XCTestCase {
    func testHistoryKeepsNewestEntriesAndExportsInCaptureOrder() {
        var history = MonitorHistory<String>(capacity: 3)
        for line in ["first", "second", "third", "fourth"] {
            history.append(line)
        }
        XCTAssertEqual(Array(history.suffix(2).reversed()), ["fourth", "third"])
        XCTAssertEqual(Array(history), ["second", "third", "fourth"])

        history.removeAll()
        XCTAssertTrue(history.isEmpty)
        history.append("after clear")
        XCTAssertEqual(Array(history), ["after clear"])
    }

    func testTraceSeparatesCaptureFrameAndPostingFromPassiveObservation() throws {
        let trace = ScrollMonitorTrace()
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 12, wheel2: -7, wheel3: 0
        ))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 12)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -7)
        event.setDoubleValueField(TrackpadEventField.rawY, value: 9.25)
        var samples: [ScrollMonitorSample] = []

        trace.record(event, stage: .captured)
        trace.drain(into: &samples)
        XCTAssertTrue(samples.isEmpty)

        trace.setRecording(true)
        trace.record(event, stage: .captured)
        trace.recordFrame(y: 3.25, x: -1.75)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 3)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        trace.record(event, stage: .postedToProcess, targetPID: 42)
        trace.record(event, stage: .postedToHID)
        trace.record(event, stage: .observed)
        trace.setRecording(false)
        trace.recordFrame(y: 0, x: 0)
        trace.drain(into: &samples)

        XCTAssertEqual(samples.map(\.stage), [.captured, .frame, .postedToProcess, .postedToHID, .observed])
        XCTAssertEqual(samples.map { $0.stage.lane }, [.input, .frame, .output, .output, nil])
        XCTAssertEqual(samples.map(\.y), [12, 3.25, 3, 3, 3])
        XCTAssertEqual(samples[1].x, -1.75)
        XCTAssertEqual(samples[0].fields?.raw.y, 9.25)
        XCTAssertEqual(samples[2].fields?.targetPID, 42)
        XCTAssertEqual(samples[3].fields?.phase, 1)
        XCTAssertTrue(samples[2].logLine(since: 0).contains("postToPid"))
        XCTAssertEqual(samples.map(\.time), samples.map(\.time).sorted())
    }

    func testTraceReportsOverflowOnceAndKeepsRecordingAfterDraining() {
        let trace = ScrollMonitorTrace(pendingLimit: 2)
        var samples: [ScrollMonitorSample] = []
        trace.setRecording(true)
        for index in 0...2 { trace.recordFrame(y: Double(index), x: 0) }

        XCTAssertEqual(trace.drain(into: &samples), 1)
        XCTAssertEqual(samples.map(\.y), [0, 1])
        trace.recordFrame(y: 3, x: 0)
        XCTAssertEqual(trace.drain(into: &samples), 0)
        XCTAssertEqual(samples.map(\.y), [3])
    }

    func testMouseLogIncludesModifiersAndSourceData() throws {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: 32, y: 48), mouseButton: .left
        ))
        event.flags = [.maskShift, .maskCommand]
        event.setIntegerValueField(.mouseEventDeltaX, value: 4)
        event.setIntegerValueField(.mouseEventDeltaY, value: -2)
        event.setIntegerValueField(.eventSourceUserData, value: 42)
        let line = try XCTUnwrap(MonitorButtonEvent(event)).logLine(since: 0)

        XCTAssertTrue(line.contains("delta:(4,-2)"))
        XCTAssertTrue(line.contains("mods:[⇧ ⌘]"))
        XCTAssertTrue(line.contains("flags:0x"))
        XCTAssertTrue(line.contains("userData: 42"))
    }

    func testModifierLogDistinguishesPressAndRelease() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.type = .flagsChanged
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(KeyCode.optionL))
        event.flags = [.maskAlternate, .maskShift]
        let pressed = try XCTUnwrap(MonitorButtonEvent(event)).logLine(since: 0)

        event.flags = [.maskShift]
        let released = try XCTUnwrap(MonitorButtonEvent(event)).logLine(since: 0)
        XCTAssertTrue(pressed.contains("flagsChanged"))
        XCTAssertTrue(pressed.contains("phase: down"))
        XCTAssertTrue(pressed.contains("mods:[⇧ ⌥]"))
        XCTAssertTrue(released.contains("phase: up"))
    }

    func testKeyboardLogIncludesKeyCodeAndDownOrUpType() throws {
        for (keyDown, eventType) in [(true, "keyDown"), (false, "keyUp")] {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown))
            event.flags = [.maskCommand, .maskShift]
            let line = try XCTUnwrap(MonitorButtonEvent(event)).logLine(since: 0)

            XCTAssertTrue(line.contains(eventType))
            XCTAssertTrue(line.contains("key:"))
            XCTAssertTrue(line.contains("keyCode: 0"))
            XCTAssertTrue(line.contains("mods:[⇧ ⌘]"))
        }
    }

    @MainActor
    func testMonitorWindowLaysOutTimelineAndLogAtMinimumSize() throws {
        let controller = MonitorWindowController()
        let window = try XCTUnwrap(controller.window)
        XCTAssertFalse(window.isVisible)
        let monitor = try XCTUnwrap(window.contentViewController as? MonitorViewController)
        let root = monitor.view
        window.setContentSize(window.contentMinSize)
        root.layoutSubtreeIfNeeded()

        let stack = try XCTUnwrap(root.subviews.first as? NSStackView)
        let timeline = try XCTUnwrap(stack.arrangedSubviews.first { $0 is MonitorCurveView })
        let log = try XCTUnwrap(stack.arrangedSubviews.last as? NSScrollView)
        XCTAssertGreaterThanOrEqual(timeline.frame.height, 200)
        XCTAssertGreaterThanOrEqual(log.frame.height, 160)
        XCTAssertLessThanOrEqual(timeline.frame.maxX, root.bounds.width)

        let controls = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? NSStackView }.last)
        let tabs = try XCTUnwrap(controls.arrangedSubviews.first as? NSSegmentedControl)
        let shortcut = try XCTUnwrap(controls.arrangedSubviews.compactMap { $0 as? NSButton }.first)
        XCTAssertTrue(shortcut.isHidden)
        tabs.selectedSegment = 1
        XCTAssertTrue(tabs.sendAction(tabs.action, to: tabs.target))
        root.layoutSubtreeIfNeeded()
        XCTAssertFalse(shortcut.isHidden)
        XCTAssertLessThanOrEqual(shortcut.frame.maxX, controls.bounds.width)
    }
}
