//
//  PhasedTrackpadOutputTests.swift
//  MosTests
//
//  应用滚动适配器: phased 手势状态机, 事件字段, 放行字段同步, 投递路由与系统版本注册
//

import XCTest
@testable import Mos_Debug

final class PhasedTrackpadOutputTests: XCTestCase {

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

    func testAdapterTeardownWaitsForQueuedEnd() throws {
        let context = ScrollDispatchContext()
        let sink = RecordingSink()
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        XCTAssertTrue(context.capture(event: event, route: .adapter(sink), targetPID: 1))
        let ending = expectation(description: "end started")
        let release = expectation(description: "adapter teardown")
        let allowEndToFinish = DispatchSemaphore(value: 0)
        var released = false
        sink.onEnd = {
            ending.fulfill()
            XCTAssertEqual(allowEndToFinish.wait(timeout: .now() + 2), .success)
        }
        context.enqueueAdapterEnd()
        wait(for: [ending], timeout: 1)

        context.afterPendingAdapterOutput {
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(sink.calls, ["end"])
            released = true
            release.fulfill()
        }
        DispatchQueue.main.async {
            XCTAssertFalse(released)
            allowEndToFinish.signal()
        }
        wait(for: [release], timeout: 1)
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

final class VirtualTrackpadTouchReportTests: XCTestCase {
    func testBeganMovedAndLiftMatchTheLabPackets() {
        let down = VirtualTrackpadTouchReport.Position(y: 2603)
        let moved = VirtualTrackpadTouchReport.Position(xOffset: 25, y: 2400)
        let reports = [
            VirtualTrackpadTouchReport.contactReport(at: down, firstID: 1, phase: .began, milliseconds: 100),
            VirtualTrackpadTouchReport.contactReport(at: moved, firstID: 1, phase: .moved, milliseconds: 108),
        ] + VirtualTrackpadTouchReport.releaseReports(at: moved, firstID: 1, milliseconds: 116)
        XCTAssertEqual(reports.map { $0.map { String(format: "%02x", $0) }.joined() }, [
            "020000000000000331240300651d006814140a05817902006c14140a0582",
            "0200000000000003316403007e7d198814140a05819262198c14140a0582",
            "020000000000000231a403007e7d19e80000000081926219ec0000000082",
            "020000000000000231a403007e7d19000000000081",
            "020000000000000231a40300",
        ])
    }

    func testPositionKeepsBothContactsWithinTheTrackpad() {
        let position = VirtualTrackpadTouchReport.Position(xOffset: .max, y: .min)
        XCTAssertEqual(position.xOffset, 3134)
        XCTAssertEqual(position.y, 0)
    }
}

@available(macOS 15.0, *)
final class VirtualTrackpadIdentityTests: XCTestCase {
    private typealias Position = VirtualTrackpadTouchReport.Position
    private let start = Position(y: 2603)

    @MainActor
    func testSharedDeviceDeliversReportsAndKeepsTheMirroringSender() async throws {
        let device = RecordingVirtualTrackpadDevice()
        let identity = VirtualTrackpadIdentity(makeDevice: { device })
        let mirroring = PhasedTrackpadSink(identity: identity, contains: { _ in true })
        identity.retain()
        defer { identity.release() }
        identity.retain()
        let sender = try await readySender(for: identity)
        XCTAssertTrue(mirroring.isReady)

        try await identity.sendTouchGesture(from: start, moves: moves([
            Position(y: 2500), Position(xOffset: 25, y: 2400)
        ]))
        let activations = await device.activations
        let reports = await device.reports
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(reports.map(\.count), [30, 30, 30, 30, 21, 12])
        XCTAssertEqual(reports.compactMap { $0.count > 15 ? $0[15] >> 5 : nil }, [3, 4, 4, 7, 0])
        XCTAssertTrue(reports.filter { $0.count == 30 }.allSatisfy {
            ($0[20] & 0xf) == 1 && ($0[29] & 0xf) == 2
        })
        identity.release()
        XCTAssertEqual(identity.sender, sender)
        XCTAssertTrue(mirroring.isReady)
    }

    @MainActor
    func testDeviceRemainsReadyUntilTheFinalLiftReportCompletes() async throws {
        let lastReport = expectation(description: "The empty release report is in flight")
        let gate = AsyncStream<Void>.makeStream()
        let device = RecordingVirtualTrackpadDevice { report in
            guard report.count == 12 else { return }
            lastReport.fulfill()
            for await _ in gate.stream {}
        }
        let identity = VirtualTrackpadIdentity(makeDevice: { device })
        identity.retain()
        defer {
            gate.continuation.finish()
            identity.release()
        }
        let sender = try await readySender(for: identity)

        let sending = Task {
            try await identity.sendTouchGesture(from: start, moves: moves([Position(y: 2400)]))
        }
        await fulfillment(of: [lastReport], timeout: 3)
        do {
            try await identity.sendTouchGesture(from: start, moves: moves([]))
            XCTFail("An in-flight release still owns the device")
        } catch {
            XCTAssertEqual(error as? VirtualTrackpadIdentity.TouchError, .gestureInProgress)
        }

        identity.release()
        XCTAssertEqual(identity.sender, sender)
        gate.continuation.finish()
        try await sending.value
        XCTAssertNil(identity.sender)
    }

    @MainActor
    func testCancellingTheInputStreamStillLiftsBothContacts() async throws {
        let down = expectation(description: "The initial contact report started")
        let device = RecordingVirtualTrackpadDevice { report in
            if report.count > 15 && report[15] >> 5 == 3 { down.fulfill() }
        }
        let identity = VirtualTrackpadIdentity(makeDevice: { device })
        let waitingForMoves = AsyncStream<Position>.makeStream()
        identity.retain()
        defer {
            waitingForMoves.continuation.finish()
            identity.release()
        }
        let sender = try await readySender(for: identity)

        let sending = Task {
            try await identity.sendTouchGesture(from: start, moves: waitingForMoves.stream)
        }
        await fulfillment(of: [down], timeout: 3)
        sending.cancel()
        do {
            try await sending.value
            XCTFail("The gesture should report cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let reports = await device.reports
        XCTAssertEqual(reports.map(\.count), [30, 30, 21, 12])
        XCTAssertEqual(identity.sender, sender)
    }

    @MainActor
    func testVirtualTrackpadOutputConvertsWheelFramesAndLifts() async throws {
        let lifted = expectation(description: "The output submits the empty touch frame")
        let device = RecordingVirtualTrackpadDevice { report in
            if report.count == 12 { lifted.fulfill() }
        }
        let identity = VirtualTrackpadIdentity(makeDevice: { device })
        identity.retain()
        defer { identity.release() }
        let sender = try await readySender(for: identity)

        let location = CGPoint(x: 100, y: 100)
        let output = VirtualTrackpadScrollOutput(
            identity: identity, cursorLocation: { location }, naturalScrolling: { false }
        )
        for _ in 0..<6 {
            output.frame(y: 12, x: 0, at: location)
        }
        output.end(at: location)
        await fulfillment(of: [lifted], timeout: 3)

        let reports = await device.reports
        let movement = try XCTUnwrap(reports.last { $0.count == 30 && $0[15] >> 5 == 4 })
        let packed = UInt32(movement[12]) | (UInt32(movement[13]) << 8)
            | (UInt32(movement[14]) << 16) | (UInt32(movement[15]) << 24)
        XCTAssertEqual((packed >> 13) & 0x1fff, 288)
        XCTAssertEqual(reports.suffix(3).map(\.count), [30, 21, 12])
        XCTAssertEqual(identity.sender, sender)
    }

    @MainActor
    func testCoreHIDDeviceSendsGestureAndKeepsItsSender() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MOS_VIRTUAL_TRACKPAD_LIVE_TEST"] == "1",
                           "Run this test only during an agreed virtual input test window")
        try XCTSkipIf(VirtualTrackpadIdentity.multitouchDeviceID() != nil,
                      "An existing Mos virtual trackpad would make the sender ambiguous")
        let identity = VirtualTrackpadIdentity.shared
        identity.retain()
        identity.retain()
        defer {
            identity.release()
            identity.release()
        }
        let sender = try await readySender(for: identity, timeout: 6)
        let mirroring = PhasedTrackpadSink(identity: identity, contains: { _ in true })
        XCTAssertTrue(mirroring.isReady)

        let positions = AsyncStream<Position>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let producer = Task {
            for frame in 1...24 {
                try? await Task.sleep(nanoseconds: 10_000_000)
                positions.continuation.yield(Position(y: 2603 - frame * 35))
            }
            positions.continuation.finish()
        }
        defer { producer.cancel() }
        try await identity.sendTouchGesture(from: start, moves: positions.stream)
        XCTAssertEqual(identity.sender, sender)
        XCTAssertEqual(VirtualTrackpadIdentity.multitouchDeviceID(), sender)
        XCTAssertTrue(mirroring.isReady)
    }

    private func readySender(for identity: VirtualTrackpadIdentity, timeout: TimeInterval = 3) async throws -> Int64 {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while identity.sender == nil && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(identity.sender)
    }

    private func moves(_ positions: [Position]) -> AsyncStream<Position> {
        AsyncStream { continuation in
            for position in positions { continuation.yield(position) }
            continuation.finish()
        }
    }
}

@available(macOS 15.0, *)
private actor RecordingVirtualTrackpadDevice: VirtualTrackpadDevice {
    private(set) var activations = 0
    private(set) var reports: [Data] = []
    private let onReport: (Data) async throws -> Void

    init(onReport: @escaping (Data) async throws -> Void = { _ in }) {
        self.onReport = onReport
    }

    func activateTrackpad() async -> Int64? {
        activations += 1
        return 314
    }

    func sendTrackpadReport(_ report: Data) async throws {
        try Task.checkCancellation()
        reports.append(report)
        try await onReport(report)
    }
}
