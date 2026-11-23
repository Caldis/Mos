import Cocoa
import XCTest
@testable import Mos_Debug

final class EventMonitorTests: XCTestCase {
    private final class UnusedSink: ScrollOutputSink {
        func frame(y: Double, x: Double, at location: CGPoint) {}
        func end(at location: CGPoint) {}
    }

    func testHistoryKeepsSelectionByIDWhenNewRowsArriveOrRollOver() {
        var history = MonitorHistory<Int>(capacity: 3)
        [1, 2, 3].forEach { history.append($0) }
        XCTAssertEqual(history.newestIndex(matching: 2, by: { $0 }), 1)
        history.append(4)
        XCTAssertEqual(Array(history), [2, 3, 4])
        XCTAssertEqual(history.newestIndex(matching: 2, by: { $0 }), 2)
        XCTAssertNil(history.newestIndex(matching: 1, by: { $0 }))
        XCTAssertEqual(history.newest(at: 0), 4)
        history.removeAll()
        XCTAssertNil(history.newest(at: 0))
    }

    func testCapturedScrollRecordsTheActualRouteTapAndCopiesOriginalFields() throws {
        let trace = ScrollMonitorTrace()
        let event = try scrollEvent()
        let adapter = ScrollRoute.adapter(ScrollAdapterRoute(application: .current, sink: UnusedSink()))
        event.flags = .maskShift
        event.setDoubleValueField(TrackpadEventField.rawY, value: 9.25)

        trace.setRecording(true)
        trace.recordCapture(event, route: .standard)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 4)
        trace.recordCapture(event, route: adapter)

        var samples: [MonitorEvent] = []
        trace.drain(into: &samples)
        let first = try scrollSample(samples.first)
        let second = try scrollSample(samples.last)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(first.tap, .cgAnnotatedSessionEventTap)
        XCTAssertEqual(second.tap, .cgSessionEventTap)
        XCTAssertEqual(first.delta.y, 12)
        XCTAssertEqual(second.delta.y, 4)
        XCTAssertEqual(first.fields?.raw.y, 9.25)
        XCTAssertEqual(first.fields?.quartz.flags, CGEventFlags.maskShift.rawValue)
    }

    func testOverlayPreservesComputedAndPostedValuesWithoutInventingACaptureTap() throws {
        let trace = ScrollMonitorTrace()
        trace.setRecording(true)
        trace.recordFrame(y: 2.49, x: -1.75)
        let event = try scrollEvent()
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 2.49)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -1.75)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 17)
        trace.record(event, stage: .postedToProcess, targetPID: 42)
        trace.record(event, stage: .postedToHID)

        var samples: [MonitorEvent] = []
        trace.drain(into: &samples)
        let first = try scrollSample(samples.first)
        let postedEvent = try XCTUnwrap(samples.dropFirst().first)
        let posted = try scrollSample(postedEvent)
        let hid = try scrollSample(samples.last)
        XCTAssertEqual(samples.map(\.time), samples.map(\.time).sorted())
        XCTAssertEqual(first.stage, .frame)
        XCTAssertEqual(first.delta[.vertical], 2.49)
        XCTAssertEqual(first.delta[.horizontal], -1.75)
        XCTAssertNil(first.fields)
        XCTAssertEqual(posted.stage, .postedToProcess)
        XCTAssertNil(posted.tap)
        XCTAssertEqual(posted.delta.y, 2)
        XCTAssertEqual(posted.delta.x, -1)
        XCTAssertEqual(posted.postingPID, 42)
        XCTAssertEqual(posted.fields?.quartz.targetPID, 17)
        XCTAssertEqual(hid.stage, .postedToHID)
        XCTAssertNil(hid.postingPID)
        let detail = MonitorPresentation.detail(postedEvent)
        XCTAssertEqual(detail.source?.value, "postToPid")
        XCTAssertTrue(detail.fields.contains(where: { $0.title == "postToPid target PID" && $0.value == "42" }))
    }

    func testTracePauseOverflowAndClearStayWithinTheRecorder() throws {
        let trace = ScrollMonitorTrace(pendingLimit: 2)
        var events: [MonitorEvent] = []
        trace.recordFrame(y: 99, x: 0)
        XCTAssertEqual(trace.drain(into: &events), 0)
        XCTAssertTrue(events.isEmpty)

        trace.setRecording(true)
        for index in 0...2 { trace.recordFrame(y: Double(index), x: 0) }
        trace.setRecording(false)
        trace.recordFrame(y: 99, x: 0)
        XCTAssertEqual(trace.drain(into: &events), 1)
        XCTAssertEqual(events.count, 2)

        trace.setRecording(true)
        trace.recordFrame(y: 3, x: 0)
        let cutoff = trace.clear()
        trace.recordFrame(y: 4, x: 0)
        XCTAssertEqual(trace.drain(into: &events), 0)
        XCTAssertEqual(events.count, 1)
        let entry = try XCTUnwrap(events.first)
        XCTAssertGreaterThanOrEqual(entry.time, cutoff)
        XCTAssertEqual(try scrollSample(entry).delta.y, 4)
    }

    func testTimelineLookupUsesSampleTimesAfterRingWraps() {
        var history = MonitorHistory<MonitorEvent>(capacity: 3)
        for index in 1...5 {
            history.append(MonitorEvent(
                id: UInt64(index), time: Double(index),
                payload: .scroll(.init(stage: .frame, delta: MonitorDelta(x: 0, y: 1)))
            ))
        }
        XCTAssertEqual(history.events(in: 3.5...4).map(\.id), [4])
        XCTAssertEqual(history.events(in: 5...5).map(\.id), [5])
        XCTAssertTrue(history.events(in: 0...2).isEmpty)
    }

    func testButtonRowsShowTheObservingTapAndActualRawFields() throws {
        let trace = ScrollMonitorTrace()
        trace.setRecording(true)
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)
        event.flags = CGEventFlags(rawValue: 0)
        trace.recordButton(event, tap: .cgSessionEventTap)
        let modifier = try XCTUnwrap(CGEvent(source: nil))
        modifier.type = .flagsChanged
        modifier.setIntegerValueField(.keyboardEventKeycode, value: Int64(KeyCode.optionL))
        modifier.flags = .maskAlternate
        trace.recordButton(modifier, tap: .cgSessionEventTap)

        var events: [MonitorEvent] = []
        trace.drain(into: &events)
        let mouse = try XCTUnwrap(events.first)
        let keyboard = try XCTUnwrap(events.last)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(mouse.channel, .buttons)
        XCTAssertEqual(MonitorPresentation.columns(mouse, origin: 0).last, "Session Tap")
        let fields = MonitorPresentation.detail(mouse).fields
        XCTAssertTrue(fields.contains(where: { $0.title == "Event type" && $0.value == "25 · otherMouseDown" }))
        XCTAssertTrue(fields.contains(where: { $0.title == "3 Button number" && $0.value.hasPrefix("3 ·") }))
        XCTAssertTrue(fields.contains(where: { $0.title == "Flags" && $0.value == "0x0" }))
        guard case let .button(snapshot, _) = keyboard.payload else { return XCTFail("Expected a modifier sample") }
        XCTAssertTrue(snapshot.isDown)
        XCTAssertEqual(snapshot.quartz.flags, CGEventFlags.maskAlternate.rawValue)
    }

    func testSharedFastFlagFollowsRecordingLifecycle() {
        ScrollMonitorTrace.setSharedRecording(false)
        defer { ScrollMonitorTrace.setSharedRecording(false) }
        XCTAssertFalse(ScrollMonitorTrace.isRecording)
        ScrollMonitorTrace.setSharedRecording(true)
        XCTAssertTrue(ScrollMonitorTrace.isRecording)
        ScrollMonitorTrace.setSharedRecording(false)
        XCTAssertFalse(ScrollMonitorTrace.isRecording)
    }

    @MainActor
    func testNativeToolbarAndMonitorLayoutAtMinimumSize() throws {
        let controller = MonitorWindowController()
        let window = try XCTUnwrap(controller.window)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier.rawValue == "monitor.views" })
        XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier.rawValue == "monitor.commands" })

        let monitor = try XCTUnwrap(window.contentViewController as? MonitorViewController)
        let root = try XCTUnwrap(monitor.view as? NSVisualEffectView)
        window.setContentSize(window.contentMinSize)
        root.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(root.subviews.first as? NSStackView)
        XCTAssertLessThan(root.convert(content.frame, to: nil).maxY, window.contentLayoutRect.maxY)
        let timeline = try XCTUnwrap(content.arrangedSubviews.first { $0 is MonitorTimelineView })
        XCTAssertFalse(timeline.isHidden)
        XCTAssertGreaterThan(timeline.frame.height, 180)

        monitor.monitorToolbar.didSelectChannel?(.buttons)
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(timeline.isHidden)
    }

    private func scrollEvent() throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 12, wheel2: -7, wheel3: 0
        ))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 12)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -7)
        return event
    }

    private func scrollSample(_ event: MonitorEvent?) throws -> MonitorEvent.ScrollSample {
        let event = try XCTUnwrap(event)
        if case .scroll(let sample) = event.payload { return sample }
        throw NSError(domain: "EventMonitorTests", code: 1)
    }
}
