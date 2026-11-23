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
        let input = try XCTUnwrap(samples.first)
        XCTAssertEqual(MonitorPresentation.columns(input, origin: input.time), ["0.000 s", "Annotated Session Tap", "-7", "12"])
        XCTAssertEqual(MonitorPresentation.detail(input).source?.value, "Annotated Session Tap")
    }

    func testOverlayPreservesComputedAndPostedValuesWithoutInventingACaptureTap() throws {
        let trace = ScrollMonitorTrace()
        trace.setRecording(true)
        trace.recordFrame(y: 2.49, x: -1.75)
        let event = try scrollEvent()
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 2.49)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -1.75)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 17)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        trace.recordPosted(event)

        var samples: [MonitorEvent] = []
        trace.drain(into: &samples)
        let first = try scrollSample(samples.first)
        let postedEvent = try XCTUnwrap(samples.last)
        let posted = try scrollSample(postedEvent)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.map(\.time), samples.map(\.time).sorted())
        XCTAssertEqual(first.stage, .frame)
        XCTAssertEqual(first.delta[.vertical], 2.49)
        XCTAssertEqual(first.delta[.horizontal], -1.75)
        XCTAssertNil(first.fields)
        XCTAssertEqual(posted.stage, .posted)
        XCTAssertNil(posted.tap)
        XCTAssertEqual(posted.delta.y, 2)
        XCTAssertEqual(posted.delta.x, -1)
        XCTAssertEqual(posted.fields?.quartz.targetPID, 17)
        let point = try XCTUnwrap(MonitorTimelineSample(event: postedEvent))
        XCTAssertEqual(point.phase, 1)
        XCTAssertTrue(point.hasMomentum)
        let detail = MonitorPresentation.detail(postedEvent)
        XCTAssertNil(detail.source)
        XCTAssertEqual(MonitorPresentation.columns(postedEvent, origin: postedEvent.time), ["0.000 s", "-1", "2"])
        XCTAssertTrue(detail.fields.contains {
            $0.enumID == CGEventField.eventTargetUnixProcessID.rawValue
                && $0.title == "Event target PID" && $0.value == "17"
        })
        XCTAssertFalse(MonitorPresentation.export(postedEvent, origin: postedEvent.time).contains("postToPid"))
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

    func testScrollListsKeepInputAndPostedEventsSeparateAfterHistoryWraps() {
        var scroll = MonitorScrollHistory(capacity: 4)
        let stages: [ScrollMonitorStage] = [.captured, .frame, .posted, .captured, .frame]
        for (index, stage) in stages.enumerated() {
            let event = MonitorEvent(
                id: UInt64(index + 1), time: Double(index),
                payload: .scroll(.init(stage: stage, delta: MonitorDelta(x: 0, y: 1)))
            )
            scroll.append(event, stage: stage)
        }
        XCTAssertEqual(scroll.history.map(\.id), [2, 3, 4, 5])
        XCTAssertEqual(scroll.rowCount(for: .captured), 1)
        XCTAssertEqual(scroll.rowCount(for: .posted), 1)
        XCTAssertEqual(scroll.rowCount(for: .frame), 0)
        XCTAssertEqual(scroll.event(at: 0, in: .captured)?.id, 4)
        XCTAssertEqual(scroll.event(at: 0, in: .posted)?.id, 3)
        XCTAssertNil(scroll.event(at: 1, in: .captured))
        XCTAssertEqual(scroll.row(for: 4, in: .captured), 0)
        XCTAssertNil(scroll.row(for: 1, in: .captured))
        XCTAssertNil(scroll.row(for: 4, in: .posted))
        scroll.removeAll()
        XCTAssertEqual(scroll.rowCount(for: .captured), 0)
        XCTAssertEqual(scroll.rowCount(for: .posted), 0)
    }

    func testLiveTimelineKeepsMovingWithAnOlderRowSelected() {
        XCTAssertEqual(MonitorCurveView.visibleRange(endingAt: 20, duration: 5, selection: 10, recording: true), 15...20)
        XCTAssertEqual(MonitorCurveView.visibleRange(endingAt: 22, duration: 5, selection: 10, recording: true), 17...22)
        XCTAssertEqual(MonitorCurveView.visibleRange(endingAt: 22, duration: 5, selection: 10, recording: false), 6...11)
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
        XCTAssertTrue(fields.contains(where: { $0.enumID == nil && $0.title == "Event type" && $0.value == "25 · otherMouseDown" }))
        XCTAssertTrue(fields.contains {
            $0.enumID == CGEventField.mouseEventButtonNumber.rawValue
                && $0.title == "Button number" && $0.value.hasPrefix("3 ·")
        })
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
        let customItems = toolbar.items.filter { $0.itemIdentifier.rawValue.hasPrefix("monitor.") }
        XCTAssertEqual(customItems.map { $0.itemIdentifier.rawValue },
                       ["monitor.views", "monitor.capture", "monitor.clear", "monitor.export"])
        let modes = try XCTUnwrap(customItems.first?.view as? NSSegmentedControl)
        let capture = try XCTUnwrap(customItems.first { $0.itemIdentifier.rawValue == "monitor.capture" })
        if #available(macOS 11.0, *) {
            XCTAssertNotNil(modes.image(forSegment: 0))
            XCTAssertNotNil(modes.image(forSegment: 1))
            XCTAssertTrue(customItems.suffix(3).allSatisfy { $0.image != nil })
        } else {
            XCTAssertTrue(customItems.suffix(3).allSatisfy { $0.view is NSButton })
        }
        XCTAssertTrue(capture.isEnabled)
        XCTAssertTrue(customItems.suffix(2).allSatisfy { !$0.isEnabled })

        let monitor = try XCTUnwrap(window.contentViewController as? MonitorViewController)
        monitor.monitorToolbar.update(.recording, canClear: false, canExport: false)
        XCTAssertEqual(capture.toolTip, [
            NSLocalizedString("monitor-recording", comment: ""),
            NSLocalizedString("monitor-pause", comment: ""),
        ].joined(separator: " · "))
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

    @MainActor
    func testEventTableShowsRawInputByDefaultAndCanShowPostedEvents() throws {
        let events = MonitorEventTable(capture: MonitorCapture())
        let header = try XCTUnwrap(events.view.subviews.compactMap { $0 as? NSStackView }.first)
        let filter = try XCTUnwrap(header.arrangedSubviews.compactMap { $0 as? NSSegmentedControl }.first)
        let scroller = try XCTUnwrap(events.view.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertEqual(filter.selectedSegment, 0)
        XCTAssertEqual(filter.label(forSegment: 0), MonitorPresentation.stageName(.captured))
        XCTAssertEqual((scroller.documentView as? NSTableView)?.tableColumns.map(\.title), [
            NSLocalizedString("monitor-time", comment: ""), NSLocalizedString("monitor-tap", comment: ""), "ΔX", "ΔY",
        ])
        filter.selectedSegment = 1
        NSApp.sendAction(try XCTUnwrap(filter.action), to: filter.target, from: filter)
        XCTAssertEqual((scroller.documentView as? NSTableView)?.tableColumns.map(\.title), [
            NSLocalizedString("monitor-time", comment: ""), "ΔX", "ΔY",
        ])
    }

    @MainActor
    func testInspectorSeparatesFieldIDNameAndValue() throws {
        let trace = ScrollMonitorTrace()
        trace.setRecording(true)
        trace.recordPosted(try scrollEvent())
        var events: [MonitorEvent] = []
        trace.drain(into: &events)
        let event = try XCTUnwrap(events.first)
        let inspector = MonitorInspector()
        inspector.display(event)
        let content = try XCTUnwrap(inspector.view.subviews.first as? NSStackView)
        let scroller = try XCTUnwrap(content.arrangedSubviews.compactMap { $0 as? NSScrollView }.first)
        let table = try XCTUnwrap(scroller.documentView as? NSTableView)
        XCTAssertEqual(table.tableColumns.map(\.title), [
            NSLocalizedString("ID", comment: ""),
            NSLocalizedString("monitor-field", comment: ""),
            NSLocalizedString("monitor-value", comment: ""),
        ])
        let values = table.tableColumns.map { column in
            (inspector.tableView(table, viewFor: column, row: 0) as? NSTableCellView)?.textField?.stringValue
        }
        XCTAssertEqual(values, ["96", "Point Y", "12.0"])
        XCTAssertTrue(MonitorPresentation.rawText(MonitorPresentation.detail(event).fields).hasPrefix("96\tPoint Y\t12.0\n"))
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
