//
//  PhasedTrackpadOutputTests.swift
//  MosTests
//
//  应用滚动适配器: phased 手势状态机, 事件字段, 放行字段同步, 投递路由与系统版本注册
//

import XCTest
@testable import Mos_Debug

final class PhasedTrackpadOutputTests: XCTestCase {

    func testCalendarRegistrationStartsAtMacOS26() {
        let registration = ScrollAdapterRegistration(descriptor: CalendarScrollAdapter.descriptor) { nil }
        XCTAssertFalse(registration.isSupported(on: OperatingSystemVersion(majorVersion: 25, minorVersion: 9, patchVersion: 9)))
        XCTAssertTrue(registration.isSupported(on: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)))
        XCTAssertTrue(registration.isSupported(on: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)))
        XCTAssertEqual(registration.descriptor.bundleIdentifiers, ["com.apple.iCal"])
    }

    func testCalendarScopeAcceptsOnlyUnambiguousMonthOrYearSelection() {
        XCTAssertEqual(CalendarScrollScope.View.selected(in: ["month-button"]), .month)
        XCTAssertEqual(CalendarScrollScope.View.selected(in: ["year-button"]), .year)
        XCTAssertNil(CalendarScrollScope.View.selected(in: ["day-button"]))
        XCTAssertNil(CalendarScrollScope.View.selected(in: ["week-button"]))
        XCTAssertNil(CalendarScrollScope.View.selected(in: []))
        XCTAssertNil(CalendarScrollScope.View.selected(in: ["month-button", "year-button"]))
    }

    func testCalendarGestureHasSeriesBoundariesAndHorizontalCompanionDelta() throws {
        let begin = PhasedTrackpadSink.makeEvents(for: .began(y: 7, x: -3), sender: 42, profile: .calendar)
        XCTAssertEqual(begin.map { $0.type.rawValue }, [29, 29, CGEventType.scrollWheel.rawValue])
        XCTAssertEqual(begin[0].getIntegerValueField(TrackpadEventField.gestureSubtype), 61)
        XCTAssertEqual(begin[0].getIntegerValueField(TrackpadEventField.gestureSeriesType), 6)
        XCTAssertEqual(begin[1].getDoubleValueField(CGEventField(rawValue: 118)!), -3)
        XCTAssertEqual(begin[1].getDoubleValueField(CGEventField(rawValue: 119)!), 7)
        XCTAssertEqual(begin[1].getIntegerValueField(CGEventField(rawValue: 135)!), 1)
        XCTAssertEqual(begin[2].getIntegerValueField(.scrollWheelEventMomentumPhase), 0)
        XCTAssertTrue(begin.allSatisfy { ScrollUtils.shared.isSyntheticSmoothEvent($0) })

        let change = PhasedTrackpadSink.makeEvents(for: .changed(y: 2, x: 0), sender: 42, profile: .calendar)
        XCTAssertEqual(change.count, 2)
        let end = PhasedTrackpadSink.makeEvents(for: .ended, sender: 42, profile: .calendar)
        XCTAssertEqual(end.count, 3)
        XCTAssertEqual(end[1].getIntegerValueField(.scrollWheelEventScrollPhase), 4)
        XCTAssertEqual(end[2].getIntegerValueField(TrackpadEventField.gestureSubtype), 62)
    }

    func testCompatibilitySwitchRespectsGlobalApplicationInheritanceAndAllowlist() {
        let global = OPTIONS_SCROLL_DEFAULT()
        let application = Application(path: "/Applications/Calendar.app")
        XCTAssertTrue(ScrollAdapterPolicy.isEnabled(application: nil, global: global, allowlist: false))
        XCTAssertFalse(ScrollAdapterPolicy.isEnabled(application: nil, global: global, allowlist: true))
        global.smoothAppCompatibility = false
        XCTAssertFalse(ScrollAdapterPolicy.isEnabled(application: application, global: global, allowlist: false))
        application.inherit = false
        XCTAssertTrue(ScrollAdapterPolicy.isEnabled(application: application, global: global, allowlist: true))
        application.scroll.smoothAppCompatibility = false
        global.smoothAppCompatibility = true
        XCTAssertFalse(ScrollAdapterPolicy.isEnabled(application: application, global: global, allowlist: false))
    }

    func testOlderApplicationProfileKeepsCompatibilityDefaultAndExplicitOptOutRoundTrips() throws {
        let application = Application(path: "/Applications/Calendar.app")
        let encoder = JSONEncoder()
        let data = try encoder.encode(application)
        let decoded = try JSONDecoder().decode(Application.self, from: data)
        XCTAssertNil(decoded.scroll.smoothAppCompatibility)
        XCTAssertTrue(decoded.scroll.usesApplicationScrollAdapters)
        application.scroll.smoothAppCompatibility = false
        let optOut = try JSONDecoder().decode(Application.self, from: encoder.encode(application))
        XCTAssertFalse(optOut.scroll.usesApplicationScrollAdapters)
    }

    func testResolvedSettingsKeepReverseIndependentOfSmoothingAndBlockHotkey() {
        let global = OPTIONS_SCROLL_DEFAULT()
        global.smooth = false
        global.reverse = true
        let reverseOnly = ScrollResolvedSettings(application: nil, global: global, allowlist: false, blockSmooth: false)
        XCTAssertFalse(reverseOnly.smooth)
        XCTAssertFalse(reverseOnly.smoothVertical)
        XCTAssertTrue(reverseOnly.reverseVertical)
        global.smooth = true
        let blocked = ScrollResolvedSettings(application: nil, global: global, allowlist: false, blockSmooth: true)
        XCTAssertFalse(blocked.smooth)
        XCTAssertTrue(blocked.reverseVertical)
        let excluded = ScrollResolvedSettings(application: nil, global: global, allowlist: true, blockSmooth: false)
        XCTAssertFalse(excluded.smooth)
        XCTAssertFalse(excluded.reverseVertical)
    }

    func testResolvedSettingsUseIndependentApplicationAxesAndParameters() {
        let global = OPTIONS_SCROLL_DEFAULT()
        global.smooth = false
        global.reverse = false
        let application = Application(path: "/Applications/Calendar.app")
        application.inherit = false
        application.scroll.smoothVertical = false
        application.scroll.reverseHorizontal = false
        application.scroll.speed = 1.5
        let own = ScrollResolvedSettings(application: application, global: global, allowlist: true, blockSmooth: false)
        XCTAssertTrue(own.smooth)
        XCTAssertFalse(own.smoothVertical)
        XCTAssertTrue(own.smoothHorizontal)
        XCTAssertTrue(own.reverseVertical)
        XCTAssertFalse(own.reverseHorizontal)
        XCTAssertEqual(own.speed, 1.5)
        application.inherit = true
        let inherited = ScrollResolvedSettings(application: application, global: global, allowlist: true, blockSmooth: false)
        XCTAssertFalse(inherited.smooth)
        XCTAssertFalse(inherited.reverseVertical)
    }

    func testAdapterDestinationChangesRequireASeparateSession() throws {
        let context = ScrollDispatchContext()
        let first = RecordingSink()
        let second = RecordingSink()
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        XCTAssertTrue(context.capture(event: event, route: .adapter(first), targetPID: 10))
        XCTAssertTrue(context.hasAdapterSession)
        XCTAssertFalse(context.isAdapterDestinationChanging(to: .adapter(first), targetPID: 10))
        XCTAssertTrue(context.isAdapterDestinationChanging(to: .adapter(first), targetPID: 11))
        XCTAssertTrue(context.isAdapterDestinationChanging(to: .adapter(second), targetPID: 10))
        XCTAssertTrue(context.isAdapterDestinationChanging(to: .process, targetPID: 10))
        context.clearContext()
        XCTAssertFalse(context.hasAdapterSession)
        XCTAssertFalse(context.isAdapterDestinationChanging(to: .adapter(second), targetPID: 11))
    }

    // MARK: - PhasedTrackpadGesture

    func testSubPixelFramesCarryOverUntilOnePixel() {
        var gesture = PhasedTrackpadGesture()
        XCTAssertEqual(gesture.advance(y: 0.4, x: 0), [])
        XCTAssertFalse(gesture.isOpen)
        XCTAssertEqual(gesture.advance(y: 0.7, x: 0), [.interrupt, .mayBegin, .began(y: 1, x: 0)])
        XCTAssertTrue(gesture.isOpen)
        // 剩余 0.1 与本帧 0.95 合计 1.05
        XCTAssertEqual(gesture.advance(y: 0.95, x: 0), [.changed(y: 1, x: 0)])
    }

    func testNegativeFramesTruncateTowardZero() {
        var gesture = PhasedTrackpadGesture()
        XCTAssertEqual(gesture.advance(y: -2.6, x: 1.2), [.interrupt, .mayBegin, .began(y: -2, x: 1)])
        XCTAssertEqual(gesture.advance(y: -0.5, x: 0), [.changed(y: -1, x: 0)])
    }

    func testEndClosesOpenGestureOnce() {
        var gesture = PhasedTrackpadGesture()
        _ = gesture.advance(y: 3, x: 0)
        XCTAssertEqual(gesture.end(), [.ended])
        XCTAssertEqual(gesture.end(), [])
        XCTAssertFalse(gesture.isOpen)
    }

    func testEndWithoutGestureDiscardsRemainder() {
        var gesture = PhasedTrackpadGesture()
        XCTAssertEqual(gesture.advance(y: 0.6, x: 0), [])
        XCTAssertEqual(gesture.end(), [])
        XCTAssertEqual(gesture.advance(y: 0.6, x: 0), [])
    }

    func testNewGestureStartsWithInterruptAfterEnd() {
        var gesture = PhasedTrackpadGesture()
        _ = gesture.advance(y: 2, x: 0)
        _ = gesture.end()
        XCTAssertEqual(gesture.advance(y: 2, x: 0), [.interrupt, .mayBegin, .began(y: 2, x: 0)])
    }

    func testDiscardClosesGestureWithoutEvents() {
        var gesture = PhasedTrackpadGesture()
        _ = gesture.advance(y: 2.5, x: 0)
        gesture.discard()
        XCTAssertFalse(gesture.isOpen)
        XCTAssertEqual(gesture.end(), [])
        // 余量同时清空, 新手势从 interrupt 开始
        XCTAssertEqual(gesture.advance(y: 1, x: 0), [.interrupt, .mayBegin, .began(y: 1, x: 0)])
    }

    // MARK: - 坐标换算

    func testGlobalPointConvertsToAppKitScreenPoint() {
        // 主屏高 1117: 全局坐标 (左上原点) y=100 对应 AppKit 屏幕坐标 (左下原点) y=1017; 主屏上方的外接屏 y 为负
        XCTAssertEqual(IPhoneMirroringAdapter.screenPoint(fromGlobal: CGPoint(x: 50, y: 100), primaryScreenHeight: 1117), NSPoint(x: 50, y: 1017))
        XCTAssertEqual(IPhoneMirroringAdapter.screenPoint(fromGlobal: CGPoint(x: 2700, y: -233), primaryScreenHeight: 1117), NSPoint(x: 2700, y: 1350))
    }

    // MARK: - 标准路径跳过

    func testStandardPathSkipsOnlyTheEventPassedThroughByHIDTap() throws {
        let center = ScrollAdapterCenter()
        let handled = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        handled.timestamp = 1_000
        let other = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        other.timestamp = 2_000
        center.setPassthroughTimestampForTests(1_000, armed: true)
        XCTAssertTrue(center.screenStandardScroll(handled))
        XCTAssertFalse(center.screenStandardScroll(other))
        center.setPassthroughTimestampForTests(1_000, armed: false)
        XCTAssertTrue(center.screenStandardScroll(handled), "A settings change between tap callbacks must not reverse the event twice")
        XCTAssertFalse(center.screenStandardScroll(handled))
    }

    // MARK: - 事件字段

    func testScrollEventKeepsPointDeltaAfterLineDelta() throws {
        let event = try XCTUnwrap(PhasedTrackpadSink.makeScroll(y: 3, x: -2, phase: 2, momentum: 0, sender: 42))
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -2)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), -1)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 0.3, accuracy: 0.001)
    }

    func testScrollEventCarriesMirroringFields() throws {
        let event = try XCTUnwrap(PhasedTrackpadSink.makeScroll(y: 5, x: 1, phase: 1, momentum: 0, sender: 4_295_510_148))
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.acceleratedY), 5)
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.rawY), 5)
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.acceleratedX), 1)
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.rawX), 1)
        XCTAssertEqual(event.getIntegerValueField(TrackpadEventField.sender), 4_295_510_148)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventScrollPhase), 1)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventMomentumPhase), 0)
        XCTAssertTrue(ScrollUtils.shared.isSyntheticSmoothEvent(event))
        // 不写入 location: 保留创建时的光标位置, 避免 HID 层投递把光标锁在原地
        let cursor = try XCTUnwrap(CGEvent(source: nil)).location
        XCTAssertEqual(event.location.x, cursor.x, accuracy: 1)
        XCTAssertEqual(event.location.y, cursor.y, accuracy: 1)
    }

    func testStepsMapToPhases() {
        func phases(_ step: PhasedTrackpadGesture.Step) -> [Int64] {
            return PhasedTrackpadSink.makeEvents(for: step, sender: 1)
                .filter { $0.type == .scrollWheel }
                .map { $0.getIntegerValueField(.scrollWheelEventScrollPhase) }
        }
        XCTAssertEqual(phases(.interrupt), [0, 128, 8])
        XCTAssertEqual(phases(.mayBegin), [128])
        XCTAssertEqual(phases(.began(y: 1, x: 0)), [1])
        XCTAssertEqual(phases(.changed(y: 1, x: 0)), [2])
        XCTAssertEqual(phases(.ended), [4])
        let interruptMomentum = PhasedTrackpadSink.makeEvents(for: .interrupt, sender: 1)
            .filter { $0.type == .scrollWheel }
            .map { $0.getIntegerValueField(.scrollWheelEventMomentumPhase) }
        XCTAssertEqual(interruptMomentum, [3, 0, 0])
    }

    func testEveryScrollStepHasGestureCompanion() {
        let events = PhasedTrackpadSink.makeEvents(for: .changed(y: 2, x: 0), sender: 1)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].type.rawValue, 29)
        XCTAssertEqual(events[1].getIntegerValueField(TrackpadEventField.gesturePhase), 2)
    }

    // MARK: - 放行事件

    func testPassthroughReverseNegatesRawFields() throws {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 1, wheel3: 0))
        event.setDoubleValueField(TrackpadEventField.acceleratedY, value: 4)
        event.setDoubleValueField(TrackpadEventField.rawY, value: 1)
        event.setDoubleValueField(TrackpadEventField.acceleratedX, value: 2)
        PhasedTrackpadSink.syncRawFields(event, reverseY: true, reverseX: false, clearY: false, clearX: false)
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.acceleratedY), -4)
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.rawY), -1)
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.acceleratedX), 2)
    }

    func testPassthroughClearZeroesRawFields() throws {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 1, wheel2: 1, wheel3: 0))
        event.setDoubleValueField(TrackpadEventField.acceleratedX, value: 3)
        event.setDoubleValueField(TrackpadEventField.rawX, value: 1)
        PhasedTrackpadSink.syncRawFields(event, reverseY: false, reverseX: true, clearY: false, clearX: true)
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.acceleratedX), 0)
        XCTAssertEqual(event.getDoubleValueField(TrackpadEventField.rawX), 0)
    }

    // MARK: - 投递上下文

    func testAdapterCaptureUsesExplicitTargetPIDAndSink() throws {
        let context = ScrollDispatchContext()
        let sink = RecordingSink()
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        XCTAssertTrue(context.capture(event: event, route: .adapter(sink), targetPID: 4242))
        let snapshot = try XCTUnwrap(context.preparePostingSnapshot())
        XCTAssertEqual(snapshot.targetPID, 4242)
        XCTAssertTrue(snapshot.route.sink === sink)
    }

    func testDefaultCaptureKeepsProcessRoute() throws {
        let context = ScrollDispatchContext()
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 77)
        XCTAssertTrue(context.capture(event: event))
        let snapshot = try XCTUnwrap(context.preparePostingSnapshot())
        XCTAssertEqual(snapshot.targetPID, 77)
        XCTAssertNil(snapshot.route.sink)
    }

    func testAdapterFramesAndEndReachSinkInOrder() throws {
        let context = ScrollDispatchContext()
        let sink = RecordingSink()
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        XCTAssertTrue(context.capture(event: event, route: .adapter(sink), targetPID: 1))
        let snapshot = try XCTUnwrap(context.preparePostingSnapshot())
        let done = expectation(description: "drained")
        sink.onEnd = { done.fulfill() }
        let framesDone = expectation(description: "frames")
        sink.onFrame = { if sink.calls.count == 2 { framesDone.fulfill() } }
        context.enqueueAdapterFrame(snapshot, sink: sink, y: 3, x: 0)
        context.enqueueAdapterFrame(snapshot, sink: sink, y: 5, x: 0)
        wait(for: [framesDone], timeout: 1)
        // 结束请求推进代次, 之后才到达的旧代次帧被丢弃
        context.enqueueAdapterEnd()
        context.enqueueAdapterFrame(snapshot, sink: sink, y: 7, x: 0)
        wait(for: [done], timeout: 1)
        let drained = expectation(description: "drained after end")
        sink.onEnd = { drained.fulfill() }
        context.enqueueAdapterEnd()
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(sink.calls, ["frame 3.0", "frame 5.0", "end", "end"])
    }

    func testStaleAdapterFrameIsDroppedButEndIsDelivered() throws {
        let context = ScrollDispatchContext()
        let sink = RecordingSink()
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        XCTAssertTrue(context.capture(event: event, route: .adapter(sink), targetPID: 1))
        let snapshot = try XCTUnwrap(context.preparePostingSnapshot())
        let done = expectation(description: "drained")
        sink.onEnd = { done.fulfill() }
        // 会话结束时代次推进, 旧代次的帧被丢弃, 结束请求不受代次影响
        context.advanceGeneration()
        context.enqueueAdapterFrame(snapshot, sink: sink, y: 5, x: 0)
        context.enqueueAdapterEnd()
        wait(for: [done], timeout: 1)
        XCTAssertEqual(sink.calls, ["end"])
    }

    func testEndWithoutAdapterSessionIsNotQueued() {
        let context = ScrollDispatchContext()
        context.enqueueAdapterEnd()
        XCTAssertNil(context.preparePostingSnapshot())
    }

    // MARK: - 系统版本注册

    func testRegistrationRespectsMinimumSystemVersion() {
        let registration = ScrollAdapterRegistration(
            descriptor: ScrollAdapterDescriptor(identifier: "test", bundleIdentifiers: ["a.b"],
                                                minimumSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)),
            make: { nil })
        XCTAssertFalse(registration.isSupported(on: OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0)))
        XCTAssertTrue(registration.isSupported(on: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)))
        XCTAssertTrue(registration.isSupported(on: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)))
    }

    func testIPhoneMirroringRequiresMacOS15() {
        XCTAssertEqual(IPhoneMirroringAdapter.descriptor.minimumSystemVersion.majorVersion, 15)
        XCTAssertEqual(IPhoneMirroringAdapter.descriptor.bundleIdentifiers, ["com.apple.ScreenContinuity"])
    }

    func testCenterStaysIdleWhenNoRegistrationIsSupported() {
        let center = ScrollAdapterCenter()
        let future = ScrollAdapterRegistration(
            descriptor: ScrollAdapterDescriptor(identifier: "future", bundleIdentifiers: ["a.b"],
                                                minimumSystemVersion: OperatingSystemVersion(majorVersion: 99, minorVersion: 0, patchVersion: 0)),
            make: { XCTFail("unsupported adapter must not be created"); return nil })
        center.start(registrations: [future])
        XCTAssertFalse(center.isStarted)
        XCTAssertFalse(center.isArmed)
    }

    // MARK: - 虚拟设备握手

    func testHandshakeCommandParsing() {
        XCTAssertEqual(VirtualTrackpadDescriptor.command(reportID: 0x01, data: [0xDB]), 0xDB)
        XCTAssertEqual(VirtualTrackpadDescriptor.command(reportID: nil, data: [0x01, 0xD9]), 0xD9)
        XCTAssertNil(VirtualTrackpadDescriptor.command(reportID: 0x02, data: [0x02, 0x01]))
    }

    func testHandshakeReplyForPendingQuery() {
        let pending = VirtualTrackpadDescriptor.setReply(for: 0xD9)
        XCTAssertEqual(VirtualTrackpadDescriptor.getReply(for: 0x01, pending: pending), VirtualTrackpadDescriptor.surface)
        XCTAssertEqual(VirtualTrackpadDescriptor.getReply(for: 0x02, pending: []), [0x02, 0x01])
    }
}

private final class RecordingSink: ScrollOutputSink {
    var calls: [String] = []
    var onEnd: (() -> Void)?
    var onFrame: (() -> Void)?
    func frame(y: Double, x: Double, at location: CGPoint) { calls.append("frame \(y)"); onFrame?() }
    func end(at location: CGPoint) { calls.append("end"); onEnd?() }
}
