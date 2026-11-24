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
        event.timestamp = 4_012_345_678
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
        XCTAssertEqual(first.captureTap, .cgAnnotatedSessionEventTap)
        XCTAssertEqual(second.captureTap, .cgSessionEventTap)
        XCTAssertEqual(first.delta.y, 12)
        XCTAssertEqual(second.delta.y, 4)
        XCTAssertEqual(first.fields?.raw.y, 9.25)
        XCTAssertEqual(first.fields?.quartz.flags, CGEventFlags.maskShift.rawValue)
        XCTAssertEqual(first.fields?.quartz.timestamp, 4_012_345_678)
        let input = try XCTUnwrap(samples.first)
        XCTAssertEqual(MonitorPresentation.columns(input, origin: input.time), ["0.000 s", "Annotated Session Tap", "-7", "12"])
        let columns = MonitorPresentation.columnDefinitions(for: .scroll)
        let captureTap = try XCTUnwrap(columns.first { $0.id == "captureTap" })
        XCTAssertEqual(captureTap.value(input, input.time), "Annotated Session Tap")
        XCTAssertEqual(captureTap.title, NSLocalizedString("monitor-capture-tap", comment: ""))
        let time = try XCTUnwrap(columns.first { $0.id == "time" })
        let localTime = try XCTUnwrap(Calendar(identifier: .gregorian).date(
            bySettingHour: 13, minute: 24, second: 56, of: input.recordedAt
        )).addingTimeInterval(0.125)
        let timedInput = MonitorEvent(id: input.id, time: input.time, recordedAt: localTime, payload: input.payload)
        XCTAssertEqual(time.value(timedInput, input.time), "13:24:56.125")
        for field in MonitorPresentation.rawFields(input) {
            let column = try XCTUnwrap(columns.first { $0.title == field.title })
            XCTAssertEqual(column.enumID, field.enumID)
            XCTAssertEqual(column.value(input, input.time), field.value)
        }
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
        trace.recordPosted(event, to: .process(17))

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
        XCTAssertNil(posted.captureTap)
        XCTAssertEqual(posted.deliveryTarget, .process(17))
        XCTAssertEqual(posted.delta.y, 2)
        XCTAssertEqual(posted.delta.x, -1)
        XCTAssertEqual(posted.fields?.quartz.targetPID, 17)
        let point = try XCTUnwrap(MonitorTimelineSample(event: postedEvent))
        XCTAssertEqual(point.phase, 1)
        XCTAssertTrue(point.hasMomentum)
        let captureTap = try XCTUnwrap(MonitorPresentation.columnDefinitions(for: .scroll).first { $0.id == "captureTap" })
        XCTAssertNil(captureTap.value(postedEvent, postedEvent.time))
        XCTAssertEqual(MonitorPresentation.columns(postedEvent, origin: postedEvent.time), ["0.000 s", "-1", "2"])
        XCTAssertTrue(MonitorPresentation.rawFields(postedEvent).contains {
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

    func testDeliveryTargetDistinguishesPostingArgumentFromEventTargetPID() throws {
        let trace = ScrollMonitorTrace()
        trace.setRecording(true)
        let event = try scrollEvent()
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 71)
        trace.recordCapture(event, route: .standard)
        trace.recordPosted(event, to: .process(42))
        trace.recordPosted(event, to: .tap(.cghidEventTap))
        var events: [MonitorEvent] = []
        trace.drain(into: &events)
        XCTAssertEqual(events.count, 3)
        let captured = try XCTUnwrap(events.first)
        let direct = try XCTUnwrap(events.dropFirst().first)
        let tapped = try XCTUnwrap(events.last)
        let columns = MonitorPresentation.columnDefinitions(for: .scroll)
        let captureTap = try XCTUnwrap(columns.first { $0.id == "captureTap" })
        let target = try XCTUnwrap(columns.first { $0.id == "postTap" })
        let targetPID = try XCTUnwrap(columns.first { $0.enumID == CGEventField.eventTargetUnixProcessID.rawValue })
        XCTAssertNil(captureTap.value(tapped, tapped.time))
        XCTAssertNil(target.displayTarget?(captured))
        XCTAssertEqual(target.displayTarget?(direct), .process(42))
        XCTAssertEqual(target.displayTarget?(tapped), .tap(.cghidEventTap))
        XCTAssertEqual(target.value(tapped, tapped.time), "HID Tap")
        XCTAssertEqual(targetPID.displayTarget?(direct), .process(71))
        XCTAssertEqual(targetPID.value(direct, direct.time), "71")
        XCTAssertEqual(target.title, NSLocalizedString("monitor-post-tap", comment: ""))
        let output = MonitorPresentation.stageName(.posted)
        let directExport = MonitorPresentation.export(direct, origin: direct.time)
        XCTAssertTrue(directExport.hasPrefix("0.000 s\t\(output)\t42\t"))
        XCTAssertTrue(directExport.contains("\tEvent target PID\t71\n"))
        let tapExport = MonitorPresentation.export(tapped, origin: tapped.time)
        XCTAssertTrue(tapExport.hasPrefix("0.000 s\t\(output)\tHID Tap\t"))
    }

    func testTimelineLookupUsesSampleTimesAfterRingWraps() {
        var history = MonitorHistory<MonitorEvent>(capacity: 3)
        for index in 1...5 {
            history.append(MonitorEvent(
                id: UInt64(index), time: Double(index), recordedAt: Date(timeIntervalSince1970: 0),
                payload: .scroll(.init(stage: .frame, delta: MonitorDelta(x: 0, y: 1)))
            ))
        }
        XCTAssertEqual(history.events(in: 3.5...4).map(\.id), [4])
        XCTAssertEqual(history.events(in: 5...5).map(\.id), [5])
        XCTAssertTrue(history.events(in: 0...2).isEmpty)
    }

    func testScrollFiltersReadTheSameOrderedHistoryAfterItWraps() {
        var scroll = MonitorScrollHistory(capacity: 4)
        let stages: [ScrollMonitorStage] = [.captured, .frame, .posted, .captured, .frame]
        for (index, stage) in stages.enumerated() {
            let event = MonitorEvent(
                id: UInt64(index + 1), time: Double(index), recordedAt: Date(timeIntervalSince1970: 0),
                payload: .scroll(.init(stage: stage, delta: MonitorDelta(x: 0, y: 1)))
            )
            scroll.append(event, stage: stage)
        }
        XCTAssertEqual(scroll.history.map(\.id), [2, 3, 4, 5])
        XCTAssertEqual(scroll.rowCount(for: .captured), 1)
        XCTAssertEqual(scroll.rowCount(for: .posted), 1)
        XCTAssertEqual(scroll.rowCount(for: .all), 2)
        XCTAssertEqual(scroll.rowCount(for: []), 0)
        XCTAssertEqual(scroll.event(at: 0, in: .all)?.id, 4)
        XCTAssertEqual(scroll.event(at: 1, in: .all)?.id, 3)
        XCTAssertEqual(scroll.row(for: 3, in: .all), 1)
        XCTAssertNil(scroll.row(for: 1, in: .all))
        XCTAssertEqual(scroll.event(at: 0, in: .captured)?.id, 4)
        XCTAssertEqual(scroll.event(at: 0, in: .posted)?.id, 3)
        XCTAssertNil(scroll.event(at: 1, in: .captured))
        XCTAssertEqual(scroll.row(for: 4, in: .captured), 0)
        XCTAssertNil(scroll.row(for: 1, in: .captured))
        XCTAssertNil(scroll.row(for: 4, in: .posted))
        scroll.removeAll()
        XCTAssertEqual(scroll.rowCount(for: .captured), 0)
        XCTAssertEqual(scroll.rowCount(for: .posted), 0)
        XCTAssertEqual(scroll.rowCount(for: .all), 0)
    }

    func testLiveTimelineKeepsMovingWithAnOlderRowSelected() {
        XCTAssertEqual(MonitorCurveView.visibleRange(endingAt: 20, duration: 5, selection: 10, recording: true), 15...20)
        XCTAssertEqual(MonitorCurveView.visibleRange(endingAt: 22, duration: 5, selection: 10, recording: true), 17...22)
        XCTAssertEqual(MonitorCurveView.visibleRange(endingAt: 22, duration: 5, selection: 10, recording: false), 6...11)
    }

    @MainActor
    func testZeroDeltaPostedEventLeavesBaselineClear() throws {
        let curve = MonitorCurveView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))

        func pixels() throws -> Data {
            let context = try XCTUnwrap(CGContext(
                data: nil, width: 480, height: 200, bitsPerComponent: 8, bytesPerRow: 480 * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            curve.displayIfNeeded()
            try XCTUnwrap(curve.layer).render(in: context)
            return Data(bytes: try XCTUnwrap(context.data), count: context.bytesPerRow * context.height)
        }

        func render(_ stage: ScrollMonitorStage, y: Double) throws -> Data {
            let event = MonitorEvent(
                id: 1, time: 0.5, recordedAt: Date(timeIntervalSince1970: 0),
                payload: .scroll(.init(stage: stage, delta: MonitorDelta(x: 0, y: y)))
            )
            let sample = try XCTUnwrap(MonitorTimelineSample(event: event))
            curve.display([sample], range: 0...1, selection: nil, waitingForInput: false)

            return try pixels()
        }

        let baseline = try render(.frame, y: 0)
        XCTAssertEqual(try render(.posted, y: 0), baseline)
        let posted = try render(.posted, y: 1)
        XCTAssertNotEqual(posted, baseline)
        curve.advance(to: 1.1)
        XCTAssertNotEqual(try pixels(), posted)
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
        let columns = MonitorPresentation.columnDefinitions(for: .buttons)
        let type = try XCTUnwrap(columns.first { $0.id == "stage" })
        let captureTap = try XCTUnwrap(columns.first { $0.id == "captureTap" })
        for event in [mouse, keyboard] {
            XCTAssertEqual(type.value(event, event.time), NSLocalizedString("monitor-captured", comment: ""))
            XCTAssertEqual(captureTap.value(event, event.time), "Session Tap")
        }
        let fields = MonitorPresentation.rawFields(mouse)
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
    func testHUDToolbarAndMonitorLayoutAtMinimumSize() throws {
        let controller = MonitorWindowController()
        let window = try XCTUnwrap(controller.window)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.appearance?.name, .vibrantDark)
        let monitor = try XCTUnwrap(window.contentViewController as? MonitorViewController)
        let toolbar = try XCTUnwrap(window.toolbar)
        let items = toolbar.items.filter { $0.itemIdentifier.rawValue.hasPrefix("monitor.") }
        XCTAssertEqual(items.map { $0.itemIdentifier.rawValue },
                       ["monitor.views", "monitor.capture", "monitor.clear", "monitor.export"])
        let modes = try XCTUnwrap(items.first?.view as? NSSegmentedControl)
        let capture = try XCTUnwrap(items.first { $0.itemIdentifier.rawValue == "monitor.capture" })
        if #available(macOS 11.0, *) {
            XCTAssertEqual(window.toolbarStyle, .unified)
            XCTAssertNotNil(modes.image(forSegment: 0))
            XCTAssertNotNil(modes.image(forSegment: 1))
            XCTAssertTrue(items.suffix(3).allSatisfy { $0.image != nil })
        } else {
            XCTAssertTrue(items.suffix(3).allSatisfy { $0.view is NSButton })
        }
        XCTAssertTrue(capture.isEnabled)
        XCTAssertTrue(items.suffix(2).allSatisfy { !$0.isEnabled })

        monitor.monitorToolbar.update(.recording, canClear: false, canExport: false)
        XCTAssertEqual(capture.toolTip, [
            NSLocalizedString("monitor-recording", comment: ""),
            NSLocalizedString("monitor-pause", comment: ""),
        ].joined(separator: " · "))
        let root = try XCTUnwrap(monitor.view as? NSVisualEffectView)
        if #available(macOS 10.14, *) { XCTAssertEqual(root.material, .hudWindow) }
        XCTAssertEqual(root.state, .active)
        window.setContentSize(window.contentMinSize)
        root.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(root.subviews.first as? NSStackView)
        XCTAssertLessThan(root.convert(content.frame, to: nil).maxY, window.contentLayoutRect.maxY)
        let timeline = try XCTUnwrap(content.arrangedSubviews.compactMap { $0 as? MonitorTimelineView }.first)
        XCTAssertFalse(timeline.isHidden)
        XCTAssertGreaterThan(timeline.frame.height, 180)
        let header = try XCTUnwrap(timeline.subviews.compactMap { $0 as? NSStackView }.first)
        if #available(macOS 26.0, *) {
            let radius = try XCTUnwrap(timeline.layer?.cornerRadius)
            XCTAssertEqual(timeline.bounds.maxY - header.frame.midY, radius, accuracy: 0.5)
            let increase = try XCTUnwrap(header.arrangedSubviews.last as? NSButton)
            let button = timeline.convert(increase.bounds, from: increase)
            XCTAssertEqual(timeline.bounds.maxX - button.midX, radius, accuracy: 0.5)
            XCTAssertEqual(timeline.bounds.maxY - button.midY, radius, accuracy: 0.5)
        }
        XCTAssertEqual(timeline.curve.frame.minY - timeline.bounds.minY, MonitorStyle.contentVerticalInset, accuracy: 0.5)

        modes.selectedSegment = MonitorChannel.buttons.rawValue
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(modes.action), to: modes.target, from: modes))
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(timeline.isHidden)
    }

    @MainActor
    func testScrollFiltersUseOneTableAndKeepTheSelectedColumns() throws {
        let events = MonitorEventTable(capture: MonitorCapture())
        let header = try XCTUnwrap(events.view.subviews.compactMap { $0 as? NSStackView }.first)
        let typeTitle = try XCTUnwrap(header.arrangedSubviews.first as? NSTextField)
        XCTAssertEqual(typeTitle.stringValue, MonitorPresentation.typeTitle)
        let filters = try XCTUnwrap(header.arrangedSubviews.compactMap { $0 as? NSStackView }.first)
        let buttons = filters.arrangedSubviews.compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.map(\.title), [
            NSLocalizedString("monitor-captured", comment: ""),
            NSLocalizedString("monitor-output", comment: ""),
        ])
        XCTAssertEqual(buttons.map(\.state), [.on, .on])
        let input = try XCTUnwrap(buttons.first)
        let posted = try XCTUnwrap(buttons.last)
        let scroller = try XCTUnwrap(events.view.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertFalse(scroller.drawsBackground)
        XCTAssertEqual(scroller.borderType, .noBorder)
        let table = try XCTUnwrap(scroller.documentView as? NSTableView)
        let menu = try XCTUnwrap(table.headerView?.menu)
        let defaults = ["time", "stage", "captureTap", "postTap", "deltaX", "deltaY"]
        XCTAssertEqual(table.tableColumns.filter { !$0.isHidden }.map { $0.identifier.rawValue }, defaults)
        XCTAssertEqual(table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("stage"))?.title, typeTitle.stringValue)
        XCTAssertTrue(table.allowsColumnReordering)

        events.menuNeedsUpdate(menu)
        let point = try XCTUnwrap(menu.items.first { $0.representedObject as? String == "field.96" })
        XCTAssertEqual(point.state, .off)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(point.action), to: point.target, from: point))
        let pointID = NSUserInterfaceItemIdentifier("field.96")
        let pointColumn = try XCTUnwrap(table.tableColumn(withIdentifier: pointID))
        XCTAssertFalse(pointColumn.isHidden)
        table.moveColumn(table.column(withIdentifier: pointID), toColumn: 0)

        input.performClick(nil)
        XCTAssertEqual(input.state, .off)
        XCTAssertEqual(posted.state, .on)
        XCTAssertTrue(scroller.documentView === table)
        XCTAssertEqual(table.tableColumns.first?.identifier, pointID)
        XCTAssertFalse(pointColumn.isHidden)

        events.menuNeedsUpdate(menu)
        let reset = try XCTUnwrap(menu.items.last)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(reset.action), to: reset.target, from: reset))
        XCTAssertEqual(table.tableColumns.filter { !$0.isHidden }.map { $0.identifier.rawValue }, defaults)
        XCTAssertTrue(pointColumn.isHidden)

        let note = NSLocalizedString("monitor-button-capture-note", comment: "")
        XCTAssertFalse(header.arrangedSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == note && !$0.isHidden
        })
        events.update(channel: .buttons, selectedID: nil)
        let noteView = try XCTUnwrap(header.arrangedSubviews.compactMap { $0 as? NSTextField }.first {
            $0.stringValue == note
        })
        XCTAssertFalse(noteView.isHidden)
        XCTAssertTrue(filters.isHidden)
        XCTAssertTrue(typeTitle.isHidden)
        let buttonTable = try XCTUnwrap(scroller.documentView as? NSTableView)
        XCTAssertEqual(buttonTable.tableColumns.filter { !$0.isHidden }.map { $0.identifier.rawValue },
                       ["time", "stage", "input", "captureTap"])
        let buttonMenu = try XCTUnwrap(buttonTable.headerView?.menu)
        events.menuNeedsUpdate(buttonMenu)
        let keyCode = try XCTUnwrap(buttonMenu.items.first {
            $0.representedObject as? String == "field.\(CGEventField.keyboardEventKeycode.rawValue)"
        })
        XCTAssertEqual(keyCode.state, .off)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(keyCode.action), to: keyCode.target, from: keyCode))
        XCTAssertEqual(buttonTable.tableColumns.filter { !$0.isHidden }.map { $0.identifier.rawValue },
                       ["time", "stage", "input", "captureTap", "field.\(CGEventField.keyboardEventKeycode.rawValue)"])
    }

    @MainActor
    func testFollowLatestButtonScrollsToTheFirstRowBelowTheHeaderInBothChannels() throws {
        class Rows: NSObject, NSTableViewDataSource {
            func numberOfRows(in tableView: NSTableView) -> Int { 80 }
        }

        let events = MonitorEventTable(capture: MonitorCapture())
        let size = NSSize(width: 600, height: 230)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentViewController = events
        window.setContentSize(size)
        events.view.layoutSubtreeIfNeeded()

        let header = try XCTUnwrap(events.view.subviews.compactMap { $0 as? NSStackView }.first)
        let button = try XCTUnwrap(header.arrangedSubviews.compactMap { $0 as? NSButton }.first)
        let inactiveFill = try XCTUnwrap(button.layer?.backgroundColor)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.toolTip, NSLocalizedString("monitor-follow-latest", comment: ""))
        let diameter = MonitorStyle.headerControlHeight
        XCTAssertEqual(button.frame.size, NSSize(width: diameter, height: diameter))
        XCTAssertEqual(button.layer?.cornerRadius, diameter / 2)
        let buttonInPane = events.view.convert(button.bounds, from: button)
        XCTAssertEqual(events.view.bounds.maxY - buttonInPane.maxY, MonitorStyle.contentVerticalInset, accuracy: 0.5)
        XCTAssertEqual(events.view.bounds.maxX - buttonInPane.maxX, MonitorStyle.padding, accuracy: 0.5)
        let scroller = try XCTUnwrap(events.view.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertGreaterThan(scroller.contentView.bounds.height, 0)
        for channel in [MonitorChannel.scroll, .buttons] {
            events.update(channel: channel, selectedID: nil)
            events.view.layoutSubtreeIfNeeded()
            let table = try XCTUnwrap(scroller.documentView as? NSTableView)
            let tableHeader = try XCTUnwrap(table.headerView)
            let rows = Rows()
            withExtendedLifetime(rows) {
                table.dataSource = rows
                table.reloadData()
                table.scrollRowToVisible(55)
                XCTAssertEqual(button.state, .off)
                XCTAssertFalse(NSLocationInRange(0, table.rows(in: table.visibleRect)))

                button.performClick(nil)
                XCTAssertEqual(button.state, .on)
                XCTAssertEqual(button.layer?.backgroundColor?.alpha, 1)
                XCTAssertTrue(NSLocationInRange(0, table.rows(in: table.visibleRect)))
                let rowBounds = scroller.convert(table.rect(ofRow: 0), from: table)
                let headerBounds = scroller.convert(tableHeader.bounds, from: tableHeader)
                XCTAssertGreaterThanOrEqual(rowBounds.minY + 0.5, headerBounds.maxY)

                table.scrollRowToVisible(55)
                button.performClick(nil)
                XCTAssertEqual(button.state, .off)
                XCTAssertEqual(button.layer?.backgroundColor, inactiveFill)
                XCTAssertFalse(NSLocationInRange(0, table.rows(in: table.visibleRect)))
            }
        }
    }

    @MainActor
    func testInspectorSeparatesFieldIDNameAndValue() throws {
        let trace = ScrollMonitorTrace()
        trace.setRecording(true)
        trace.recordPosted(try scrollEvent(), to: .tap(.cghidEventTap))
        var events: [MonitorEvent] = []
        trace.drain(into: &events)
        let event = try XCTUnwrap(events.first)
        let inspector = MonitorInspector()
        inspector.display(event)
        inspector.view.frame.size = NSSize(width: 292, height: 230)
        inspector.view.layoutSubtreeIfNeeded()
        let panel = try XCTUnwrap(inspector.view.subviews.first)
        let content = try XCTUnwrap(panel.subviews.first as? NSStackView)
        XCTAssertEqual(content.arrangedSubviews.count, 2)
        let header = try XCTUnwrap(content.arrangedSubviews.first as? NSStackView)
        let buttons = header.arrangedSubviews.compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.map(\.title), [
            NSLocalizedString("monitor-copy-raw", comment: ""),
            NSLocalizedString("monitor-close-inspector", comment: ""),
        ])
        let copy = try XCTUnwrap(buttons.first)
        let close = try XCTUnwrap(buttons.last)
        XCTAssertEqual(copy.imagePosition, .imageOnly)
        XCTAssertNotNil(copy.image)
        XCTAssertEqual(copy.toolTip, NSLocalizedString("monitor-copy-raw", comment: ""))
        let diameter = MonitorStyle.headerControlHeight
        XCTAssertEqual(copy.frame.size, NSSize(width: diameter, height: diameter))
        XCTAssertEqual(copy.layer?.cornerRadius, diameter / 2)
        XCTAssertEqual(close.frame.size, copy.frame.size)
        XCTAssertEqual(copy.frame.midY, close.frame.midY, accuracy: 0.5)
        XCTAssertLessThan(copy.frame.maxX, close.frame.minX)
        if #available(macOS 26.0, *) {
            let radius = try XCTUnwrap(panel.layer?.cornerRadius)
            let button = panel.convert(close.bounds, from: close)
            XCTAssertEqual(panel.bounds.maxX - button.midX, radius, accuracy: 0.5)
            XCTAssertEqual(panel.bounds.maxY - button.midY, radius, accuracy: 0.5)
        }
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
        XCTAssertTrue(MonitorPresentation.rawText(MonitorPresentation.rawFields(event)).hasPrefix("96\tPoint Y\t12.0\n"))
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
