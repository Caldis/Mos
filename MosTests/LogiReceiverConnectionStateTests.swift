import XCTest
@testable import Mos_Debug

final class LogiReceiverConnectionStateTests: XCTestCase {

    func testBLEIsAlwaysSendableForReceiverTargetChecks() {
        XCTAssertTrue(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .bleDirect,
            deviceIndex: 0xFF,
            pairedDevices: []
        ))
    }

    func testKnownDisconnectedReceiverTargetIsNotSendable() {
        XCTAssertFalse(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .receiver,
            deviceIndex: 0x03,
            pairedDevices: [
                .init(slot: 0x03, isConnected: false)
            ]
        ))
    }

    func testUnknownReceiverTargetDefaultsToSendable() {
        XCTAssertTrue(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .receiver,
            deviceIndex: 0x03,
            pairedDevices: []
        ))
    }

    func testReconnectWithCompleteControlCacheRefreshesReporting() {
        XCTAssertEqual(LogiDeviceSession.receiverReconnectActionForTests(
            hasReprogFeature: true,
            discoveredControlCount: 7,
            reprogControlCount: 7,
            hasInflightWork: false
        ), .refreshReporting)
    }

    func testReconnectWithPartialControlCacheRediscoveresFeatures() {
        XCTAssertEqual(LogiDeviceSession.receiverReconnectActionForTests(
            hasReprogFeature: true,
            discoveredControlCount: 3,
            reprogControlCount: 7,
            hasInflightWork: false
        ), .rediscoverFeatures)
    }

    func testReconnectWhileWorkIsInFlightDoesNothing() {
        XCTAssertEqual(LogiDeviceSession.receiverReconnectActionForTests(
            hasReprogFeature: true,
            discoveredControlCount: 7,
            reprogControlCount: 7,
            hasInflightWork: true
        ), .ignore)
    }

    func testConnectedNonCurrentSlotRetargetsWhenCurrentTargetIsDisconnected() {
        XCTAssertEqual(LogiDeviceSession.receiverConnectionNotificationActionForTests(
            currentDeviceIndex: 0x01,
            incomingDeviceIndex: 0x03,
            connected: true,
            currentTargetIsConnected: false,
            reprogInitComplete: false,
            hasInflightWork: false
        ), .retarget(0x03))
    }

    func testConnectedNonCurrentSlotDoesNotRetargetWhenCurrentTargetIsReady() {
        XCTAssertEqual(LogiDeviceSession.receiverConnectionNotificationActionForTests(
            currentDeviceIndex: 0x01,
            incomingDeviceIndex: 0x03,
            connected: true,
            currentTargetIsConnected: true,
            reprogInitComplete: true,
            hasInflightWork: false
        ), .ignore)
    }

    // MARK: - chooseReceiverTargetSlot (Phase 0 prefer-mouse 巡检游标)

    private func device(
        slot: UInt8,
        connected: Bool,
        type: UInt8
    ) -> LogiDeviceSession.ReceiverPairedDevice {
        var d = LogiDeviceSession.ReceiverPairedDevice(slot: slot)
        d.isConnected = connected
        d.deviceType = type
        return d
    }

    func testChooseTargetPrefersMouseOverLowerNumberedKeyboard() {
        // 键盘在更低号 slot, 鼠标在更高号 slot -> 选鼠标 (修复旧的锁最低号 bug)
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 1, connected: true, type: 0x01),  // Keyboard
            device(slot: 3, connected: true, type: 0x02)   // Mouse
        ]), 3)
    }

    func testChooseTargetFallsBackToFirstConnectedWhenNoMouse() {
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 2, connected: true, type: 0x01),  // Keyboard
            device(slot: 4, connected: true, type: 0x01)   // Keyboard
        ]), 2)
    }

    func testChooseTargetFallsBackToFirstConnectedWhenTypesUnknown() {
        // device-info 未到齐 (deviceType 全 0) 时回退首个在线 slot, 不退化
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 2, connected: true, type: 0x00),
            device(slot: 4, connected: true, type: 0x00)
        ]), 2)
    }

    func testChooseTargetSkipsDisconnectedMouse() {
        // 鼠标已断开, 只有键盘在线 -> 回退在线键盘, 不选断开的鼠标
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 1, connected: false, type: 0x02),  // Mouse (disconnected)
            device(slot: 3, connected: true, type: 0x01)    // Keyboard
        ]), 3)
    }

    func testChooseTargetPicksFirstConnectedMouse() {
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 2, connected: true, type: 0x02),  // Mouse
            device(slot: 5, connected: true, type: 0x02)   // Mouse
        ]), 2)
    }

    func testChooseTargetReturnsNilWhenNothingConnected() {
        XCTAssertNil(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 1, connected: false, type: 0x02),
            device(slot: 2, connected: false, type: 0x01)
        ]))
        XCTAssertNil(LogiDeviceSession.chooseReceiverTargetSlot(devices: []))
    }

    // MARK: - receiverDivertSlots (Phase 2 接管集合)

    private func device(
        slot: UInt8,
        connected: Bool,
        type: UInt8,
        pid: UInt16
    ) -> LogiDeviceSession.ReceiverPairedDevice {
        var d = LogiDeviceSession.ReceiverPairedDevice(slot: slot)
        d.isConnected = connected
        d.deviceType = type
        d.wirelessPID = pid
        return d
    }

    func testDivertSlotsIncludesOnlyConnectedBoundMice() {
        let devices = [
            device(slot: 1, connected: true, type: 0x01, pid: 0xB350),  // Keyboard -> excluded
            device(slot: 2, connected: true, type: 0x02, pid: 0x4082),  // Mouse, bound
            device(slot: 3, connected: false, type: 0x02, pid: 0x4082), // Mouse, disconnected -> excluded
            device(slot: 4, connected: true, type: 0x02, pid: 0x999),   // Mouse, no binding -> excluded
            device(slot: 5, connected: true, type: 0x02, pid: 0x4082)   // Mouse, bound
        ]
        let bound: Set<UInt16> = [0x4082]
        XCTAssertEqual(
            LogiDeviceSession.receiverDivertSlots(devices: devices) { bound.contains($0) },
            [2, 5]
        )
    }

    func testDivertSlotsEmptyWhenNoBindings() {
        let devices = [
            device(slot: 2, connected: true, type: 0x02, pid: 0x4082),
            device(slot: 3, connected: true, type: 0x02, pid: 0x4083)
        ]
        XCTAssertEqual(
            LogiDeviceSession.receiverDivertSlots(devices: devices) { _ in false },
            []
        )
    }

    func testDivertSlotsSortedAscending() {
        let devices = [
            device(slot: 5, connected: true, type: 0x02, pid: 0x4082),
            device(slot: 2, connected: true, type: 0x02, pid: 0x4082)
        ]
        XCTAssertEqual(
            LogiDeviceSession.receiverDivertSlots(devices: devices) { _ in true },
            [2, 5]
        )
    }

    // MARK: - receiverReportRoute (Phase 2 报文分发)

    func testReportRouteProcessesCurrentSlot() {
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 2, currentSlot: 2, managedSlots: [2, 5]),
            .processCurrent
        )
    }

    func testReportRouteScopesToOtherManagedSlot() {
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 5, currentSlot: 2, managedSlots: [2, 5]),
            .processScoped(5)
        )
    }

    func testReportRouteDropsUnmanagedSlot() {
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 4, currentSlot: 2, managedSlots: [2, 5]),
            .drop
        )
    }

    func testReportRouteSingleDeviceDropsNonCurrent() {
        // 单设备: managedSlots = {current}, 其它 slot 一律 drop (与旧 stale 过滤等价)
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 3, currentSlot: 1, managedSlots: [1]),
            .drop
        )
    }

    func testReportRouteDropsOutOfRangeSlot() {
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 0, currentSlot: 1, managedSlots: [1]),
            .drop
        )
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 7, currentSlot: 1, managedSlots: [1]),
            .drop
        )
    }
}
