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

    func testDivertSlotsIncludesUnknownTypeSlots() {
        // 关键回归: 接收器不返回 deviceType (寄存器 0xB5 InvalidSubID) 时类型恒为 0(未知).
        // 未知类型的鼠标必须纳入接管, 否则永不 divert (真实 USB Receiver 上的现象).
        let devices = [
            device(slot: 1, connected: true, type: 0x00, pid: 0x0000),  // 未知(实为键盘, 但类型拿不到)
            device(slot: 4, connected: true, type: 0x00, pid: 0x0000)   // 未知(实为鼠标)
        ]
        XCTAssertEqual(
            LogiDeviceSession.receiverDivertSlots(devices: devices) { _ in true },
            [1, 4]
        )
    }

    func testDivertSlotsExcludesKnownKeyboardIncludesUnknownMouse() {
        // 类型部分已知: 键盘(0x01)排除, 未知/鼠标纳入.
        let devices = [
            device(slot: 1, connected: true, type: 0x01, pid: 0x0000),  // Keyboard -> excluded
            device(slot: 4, connected: true, type: 0x00, pid: 0x0000),  // Unknown -> included
            device(slot: 5, connected: true, type: 0x02, pid: 0x0000)   // Mouse -> included
        ]
        XCTAssertEqual(
            LogiDeviceSession.receiverDivertSlots(devices: devices) { _ in true },
            [4, 5]
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

    // MARK: - controlsLookLikeMouse (类型不可知接收器上据控件识别鼠标)

    func testControlsLookLikeMouseWithLeftAndRight() {
        // 鼠标: 有 Left(0x50) + Right(0x51) + 其它
        XCTAssertTrue(LogiDeviceSession.controlsLookLikeMouse(
            cids: [0x0050, 0x0051, 0x0052, 0x0053, 0x00C3]))
    }

    func testControlsLookLikeKeyboardWithoutLeftRight() {
        // 键盘: media/backlight 类 CID, 无标准 Left/Right
        XCTAssertFalse(LogiDeviceSession.controlsLookLikeMouse(
            cids: [0x00D1, 0x00D2, 0x00E2, 0x00E5, 0x0103]))
    }

    func testControlsLookLikeMouseNeedsBothButtons() {
        XCTAssertFalse(LogiDeviceSession.controlsLookLikeMouse(cids: [0x0050]))
        XCTAssertFalse(LogiDeviceSession.controlsLookLikeMouse(cids: [0x0051]))
        XCTAssertFalse(LogiDeviceSession.controlsLookLikeMouse(cids: []))
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

    // MARK: - receiverSlotConnectionAction (Phase 4 热插拔)

    func testSlotConnectionDisconnectedManagedReleases() {
        // 已接管的 slot 断开 -> 释放其接管状态
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 4, connected: false, isDivertCandidate: false, alreadyManaged: true),
            .release(4)
        )
    }

    func testSlotConnectionDisconnectedUnmanagedIgnored() {
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 4, connected: false, isDivertCandidate: false, alreadyManaged: false),
            .ignore
        )
    }

    func testSlotConnectionReconnectUnmanagedCandidateTakesOver() {
        // 关键: 鼠标关机/切 slot 再回来 -> 未接管 + 候选 -> 重新 discovery+divert
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 4, connected: true, isDivertCandidate: true, alreadyManaged: false),
            .takeover(4)
        )
    }

    func testSlotConnectionConnectedAlreadyManagedIgnored() {
        // 防振荡: 已接管且在线的 slot 再收到 connected 通知 -> 忽略, 不重复 discovery
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 4, connected: true, isDivertCandidate: true, alreadyManaged: true),
            .ignore
        )
    }

    func testSlotConnectionConnectedNonCandidateIgnored() {
        // 键盘等非候选设备连接 -> 不接管
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 1, connected: true, isDivertCandidate: false, alreadyManaged: false),
            .ignore
        )
    }

    func testSlotConnectionOutOfRangeIgnored() {
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 0, connected: true, isDivertCandidate: true, alreadyManaged: false),
            .ignore
        )
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 7, connected: false, isDivertCandidate: false, alreadyManaged: true),
            .ignore
        )
    }
}
