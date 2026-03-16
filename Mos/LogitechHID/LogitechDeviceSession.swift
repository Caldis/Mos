//
//  LogitechDeviceSession.swift
//  Mos
//  单个 Logitech 设备的 HID++ 2.0 通信会话
//  实现 Feature Discovery, Button Divert, 事件解析
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import IOKit
import IOKit.hid

class LogitechDeviceSession {

    // MARK: - Public
    let hidDevice: IOHIDDevice
    let deviceInfo: MosInputDevice

    // MARK: - HID++ State
    private var featureIndex: [UInt16: UInt8] = [:]
    private var divertedCIDs: Set<UInt16> = []
    private var lastActiveCIDs: Set<UInt16> = []
    private var deviceIndex: UInt8 = 0x01
    private var isBLE: Bool = false

    // MARK: - Report Buffer
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private static let reportBufferSize = 64

    // MARK: - Async Discovery
    private var pendingDiscovery: [UInt16: (UInt8?) -> Void] = [:]
    private var discoveryTimer: Timer?
    private static let discoveryTimeout: TimeInterval = 5.0

    // MARK: - Reprog Controls State
    private var reprogControlCount: Int = 0
    private var reprogQueryIndex: Int = 0       // 当前正在查询的 control index
    private var discoveredControls: [ControlInfo] = []

    /// 单个可重编程按键的信息
    struct ControlInfo {
        let cid: UInt16
        let taskId: UInt16
        let flags: UInt16       // flags1 | (flags2 << 8)
        let isDivertable: Bool  // flags bit 0: 可 divert
    }

    // MARK: - HID++ Constants
    private static let featureIRoot: UInt16 = 0x0000
    private static let featureReprogV4: UInt16 = 0x1B04
    private static let hidppShortReportId: UInt8 = 0x10
    private static let hidppLongReportId: UInt8 = 0x11
    private static let hidppErrorFeatureIdx: UInt8 = 0xFF

    // MARK: - Init

    init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
        self.deviceInfo = MosInputDevice(
            vendorId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDVendorIDKey as CFString) as? Int ?? 0),
            productId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDProductIDKey as CFString) as? Int ?? 0),
            name: IOHIDDeviceGetProperty(hidDevice, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        )
    }

    deinit {
        reportBufferPtr?.deallocate()
    }

    // MARK: - Setup / Teardown

    func setup() {
        let usagePage = IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let transport = IOHIDDeviceGetProperty(hidDevice, kIOHIDTransportKey as CFString) as? String ?? ""

        // BLE 直连: device index = 0xFF (Solaar 确认)
        // USB Receiver: device index = 0x01~0x06 (按配对槽位)
        isBLE = transport.lowercased().contains("bluetooth")
        if isBLE {
            deviceIndex = 0xFF
        }

        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Setting up (usagePage: \(String(format: "0x%04X", usagePage)), usage: \(String(format: "0x%04X", usage)), transport: \(transport), devIdx: \(String(format: "0x%02X", deviceIndex)))")

        // 分配稳定的 report buffer
        reportBufferPtr = .allocate(capacity: Self.reportBufferSize)
        reportBufferPtr!.initialize(repeating: 0, count: Self.reportBufferSize)

        // 注册 Input Report 回调
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            hidDevice,
            reportBufferPtr!,
            Self.reportBufferSize,
            Self.inputReportCallback,
            context
        )

        // Feature Discovery: 查找 REPROG_CONTROLS_V4
        discoverFeature(featureId: Self.featureReprogV4) { [weak self] index in
            guard let self = self, let index = index else {
                LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] REPROG_CONTROLS_V4 not supported, skipping")
                return
            }
            self.featureIndex[Self.featureReprogV4] = index
            LogitechHIDDebugPanel.log("[\(self.deviceInfo.name)] REPROG_CONTROLS_V4 found at index \(String(format: "0x%02X", index))")
            // 开始 GetControlCount
            self.sendGetControlCount(featureIndex: index)
        }
    }

    func teardown() {
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Tearing down session")
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        pendingDiscovery.removeAll()

        // 取消所有 divert (恢复按键的默认行为)
        if let reprogIdx = featureIndex[Self.featureReprogV4] {
            for cid in divertedCIDs {
                setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
            }
        }
        divertedCIDs.removeAll()
        lastActiveCIDs.removeAll()
        discoveredControls.removeAll()
    }

    // MARK: - Input Report Callback (C function pointer)

    static let inputReportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
        guard let context = context else { return }
        let session = Unmanaged<LogitechDeviceSession>.fromOpaque(context).takeUnretainedValue()
        let data = Array(UnsafeBufferPointer(start: report, count: reportLength))
        session.handleInputReport(data)
    }

    // MARK: - HID++ Send

    private func sendShortRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8] = []) {
        var report = [UInt8](repeating: 0, count: 7)
        report[0] = Self.hidppShortReportId
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (functionId << 4) | 0x01  // FuncID | SwID
        for (i, p) in params.prefix(3).enumerated() {
            report[4 + i] = p
        }

        let hex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] TX: \(hex)")

        // IOHIDDeviceSetReport: reportID 作为独立参数, data 不含 report ID
        // 与 hidapi 一致: IOHIDDeviceSetReport(dev, type, data[0], data+1, len-1)
        let reportId = CFIndex(report[0])
        let payload = Array(report.dropFirst())

        // BLE: 先尝试 OUTPUT, 失败则 fallback 到 FEATURE report
        var result = IOHIDDeviceSetReport(
            hidDevice, kIOHIDReportTypeOutput, reportId, payload, payload.count
        )
        if result != kIOReturnSuccess && isBLE {
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] OUTPUT failed (\(String(format: "0x%08x", result))), trying FEATURE")
            result = IOHIDDeviceSetReport(
                hidDevice, kIOHIDReportTypeFeature, reportId, payload, payload.count
            )
        }
        if result != kIOReturnSuccess {
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] SetReport failed: \(String(format: "0x%08x", result))")
        }
    }

    // MARK: - Feature Discovery

    private func discoverFeature(featureId: UInt16, completion: @escaping (UInt8?) -> Void) {
        let params: [UInt8] = [UInt8(featureId >> 8), UInt8(featureId & 0xFF)]
        sendShortRequest(featureIndex: 0x00, functionId: 0, params: params)
        pendingDiscovery[featureId] = completion

        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: Self.discoveryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if let pending = self.pendingDiscovery.removeValue(forKey: featureId) {
                LogitechHIDDebugPanel.log("[\(self.deviceInfo.name)] Feature discovery timed out for \(String(format: "0x%04X", featureId))")
                pending(nil)
            }
        }
    }

    // MARK: - REPROG_CONTROLS_V4 Complete Flow
    // Step 1: GetControlCount (function 0) → count
    // Step 2: GetControlInfo (function 1, param=index) × N → CID + flags per control
    // Step 3: SetControlReporting (function 3, CID + divert flag) for each divertable CID

    /// Step 1: 发送 GetControlCount
    private func sendGetControlCount(featureIndex: UInt8) {
        sendShortRequest(featureIndex: featureIndex, functionId: 0)
    }

    /// Step 2: 发送 GetControlInfo(index)
    private func sendGetControlInfo(featureIndex: UInt8, index: Int) {
        sendShortRequest(featureIndex: featureIndex, functionId: 1, params: [UInt8(index)])
    }

    /// Step 3: SetControlReporting (divert on/off)
    private func setControlReporting(featureIndex: UInt8, cid: UInt16, divert: Bool) {
        // Solaar: function 3, params = CID(2) + flags(1) + targetCID(2)
        // flags bit 0 = divert (temporaryDiverted)
        // flags bit 4 = persistentDivert
        // 我们只设 bit 0 (临时 divert, app 退出后自动恢复)
        let flagsByte: UInt8 = divert ? 0x01 : 0x00
        sendShortRequest(featureIndex: featureIndex, functionId: 3,
                         params: [UInt8(cid >> 8), UInt8(cid & 0xFF), flagsByte])
        if divert {
            divertedCIDs.insert(cid)
        } else {
            divertedCIDs.remove(cid)
        }
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] CID \(String(format: "0x%04X", cid)) divert=\(divert ? "ON" : "OFF")")
    }

    // MARK: - Report Parsing

    func handleInputReport(_ report: [UInt8]) {
        guard report.count >= 7 else { return }
        guard report[0] == Self.hidppShortReportId || report[0] == Self.hidppLongReportId else { return }

        let hex = report.prefix(min(report.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] RX: \(hex)")

        let featureIdx = report[2]
        let functionId = report[3] >> 4   // 高 4 位 = function ID

        // Error report (feature index = 0xFF)
        if featureIdx == Self.hidppErrorFeatureIdx {
            let errorCode = report.count > 6 ? report[6] : 0
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] HID++ Error: featureIdx=\(String(format: "0x%02X", report[3])) errorCode=\(String(format: "0x%02X", errorCode))")
            for (featureId, callback) in pendingDiscovery {
                callback(nil)
                pendingDiscovery.removeValue(forKey: featureId)
            }
            return
        }

        // IRoot response (feature discovery)
        if featureIdx == 0x00 {
            handleDiscoveryResponse(report)
            return
        }

        // REPROG_CONTROLS_V4 responses & notifications
        if let reprogIdx = featureIndex[Self.featureReprogV4], featureIdx == reprogIdx {
            switch functionId {
            case 0:
                // GetControlCount response: byte[4] = count
                handleGetControlCountResponse(report)
            case 1:
                // GetControlInfo response: bytes[4..12] = control info
                handleGetControlInfoResponse(report)
            default:
                // divertedButtonsEvent notification (function varies) or other events
                handleDivertedButtonEvent(report)
            }
            return
        }
    }

    // MARK: - IRoot Response

    private func handleDiscoveryResponse(_ report: [UInt8]) {
        let discoveredIndex = report[4]

        if let (featureId, callback) = pendingDiscovery.first {
            discoveryTimer?.invalidate()
            pendingDiscovery.removeValue(forKey: featureId)
            if discoveredIndex == 0 {
                callback(nil)
            } else {
                callback(discoveredIndex)
            }
        }
    }

    // MARK: - REPROG_CONTROLS_V4 Response Handlers

    /// GetControlCount response: byte[4] = count
    private func handleGetControlCountResponse(_ report: [UInt8]) {
        reprogControlCount = Int(report[4])
        reprogQueryIndex = 0
        discoveredControls.removeAll()
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] GetControlCount = \(reprogControlCount)")

        // 开始逐个查询 control info
        if reprogControlCount > 0, let reprogIdx = featureIndex[Self.featureReprogV4] {
            sendGetControlInfo(featureIndex: reprogIdx, index: 0)
        }
    }

    /// GetControlInfo response: bytes[4..12]
    /// Format: CID(2) + TaskID(2) + Flags1(1) + Pos(1) + Group(1) + GMask(1) + Flags2(1)
    private func handleGetControlInfoResponse(_ report: [UInt8]) {
        guard report.count >= 11 else { return }

        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let taskId = (UInt16(report[6]) << 8) | UInt16(report[7])
        let flags1 = report[8]
        let flags2: UInt8 = report.count > 12 ? report[12] : 0
        let flags = UInt16(flags1) | (UInt16(flags2) << 8)
        // Solaar: bit 0 of flags = reprogrammable, bit 3 = divertable (raw_XY capable uses bit 5)
        let isDivertable = (flags & 0x08) != 0  // bit 3

        let control = ControlInfo(cid: cid, taskId: taskId, flags: flags, isDivertable: isDivertable)
        discoveredControls.append(control)

        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Control[\(reprogQueryIndex)]: CID=\(String(format: "0x%04X", cid)) TaskID=\(String(format: "0x%04X", taskId)) flags=\(String(format: "0x%04X", flags)) divertable=\(isDivertable)")

        reprogQueryIndex += 1

        if reprogQueryIndex < reprogControlCount, let reprogIdx = featureIndex[Self.featureReprogV4] {
            // 查询下一个 control
            sendGetControlInfo(featureIndex: reprogIdx, index: reprogQueryIndex)
        } else {
            // 全部查询完毕, 对所有 divertable 的按键执行 divert
            divertAllControls()
        }
    }

    /// 对所有 divertable 的 control 执行 divert
    private func divertAllControls() {
        guard let reprogIdx = featureIndex[Self.featureReprogV4] else { return }

        let divertable = discoveredControls.filter { $0.isDivertable }
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Diverting \(divertable.count)/\(discoveredControls.count) controls")

        for control in divertable {
            setControlReporting(featureIndex: reprogIdx, cid: control.cid, divert: true)
        }
    }

    // MARK: - Diverted Button Event

    /// divertedButtonsEvent: CID pairs 从 byte[4] 开始, 0x0000 结束
    private func handleDivertedButtonEvent(_ report: [UInt8]) {
        var activeCIDs: Set<UInt16> = []
        var offset = 4
        while offset + 1 < report.count {
            let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
            if cid == 0 { break }
            activeCIDs.insert(cid)
            offset += 2
        }

        // 差分检测
        let newlyPressed = activeCIDs.subtracting(lastActiveCIDs)
        let newlyReleased = lastActiveCIDs.subtracting(activeCIDs)
        lastActiveCIDs = activeCIDs

        for cid in newlyPressed {
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Button DOWN: CID \(String(format: "0x%04X", cid))")
            dispatchButtonEvent(cid: cid, isDown: true)
        }
        for cid in newlyReleased {
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Button UP: CID \(String(format: "0x%04X", cid))")
            dispatchButtonEvent(cid: cid, isDown: false)
        }
    }

    // MARK: - Event Dispatch

    private func dispatchButtonEvent(cid: UInt16, isDown: Bool) {
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)

        let mosEvent = MosInputEvent(
            type: .mouse,
            code: LogitechCIDMap.toMosCode(cid),
            modifiers: currentFlags,
            phase: isDown ? .down : .up,
            source: .hidPlusPlus,
            device: deviceInfo
        )

        let _ = MosInputProcessor.shared.process(mosEvent)

        NotificationCenter.default.post(
            name: LogitechHIDManager.buttonEventNotification,
            object: nil,
            userInfo: ["event": mosEvent]
        )
    }
}
