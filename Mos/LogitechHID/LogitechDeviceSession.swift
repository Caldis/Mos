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
    let usagePage: Int
    let usage: Int
    let transport: String

    // MARK: - HID++ State
    private var featureIndex: [UInt16: UInt8] = [:]
    private var divertedCIDs: Set<UInt16> = []
    private var lastActiveCIDs: Set<UInt16> = []
    private var deviceIndex: UInt8 = 0x01
    private var isBLE: Bool = false
    private var deviceOpened: Bool = false

    // MARK: - Report Buffer
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private static let reportBufferSize = 64

    // MARK: - Async Discovery
    private var pendingDiscovery: [UInt16: (UInt8?) -> Void] = [:]
    private var discoveryTimer: Timer?
    private static let discoveryTimeout: TimeInterval = 5.0

    // MARK: - Reprog Controls State
    private var reprogControlCount: Int = 0
    private var reprogQueryIndex: Int = 0
    private var discoveredControls: [ControlInfo] = []

    struct ControlInfo {
        let cid: UInt16
        let taskId: UInt16
        let flags: UInt16
        let isDivertable: Bool
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
        self.usagePage = IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        self.usage = IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        self.transport = IOHIDDeviceGetProperty(hidDevice, kIOHIDTransportKey as CFString) as? String ?? ""
        self.deviceInfo = MosInputDevice(
            vendorId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDVendorIDKey as CFString) as? Int ?? 0),
            productId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDProductIDKey as CFString) as? Int ?? 0),
            name: IOHIDDeviceGetProperty(hidDevice, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        )
    }

    deinit {
        if deviceOpened { IOHIDDeviceClose(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone)) }
        reportBufferPtr?.deallocate()
    }

    /// 是否为 HID++ 候选接口
    var isHIDPPCandidate: Bool {
        // USB: 只有 vendor-specific usage page 支持 HID++
        if !isBLE {
            return usagePage == 0xFF00 || usagePage == 0xFF43 || usagePage == 0xFFC0
        }
        // BLE: HID++ 复用标准 mouse interface
        return usagePage == 0x0001 && usage == 0x0002
    }

    // MARK: - Setup / Teardown

    func setup() {
        isBLE = transport.lowercased().contains("bluetooth")
        if isBLE { deviceIndex = 0xFF }

        let tag = "[\(deviceInfo.name):\(String(format: "0x%04X", usagePage))/\(String(format: "0x%04X", usage))]"
        LogitechHIDDebugPanel.log("\(tag) Setup: transport=\(transport), devIdx=\(String(format: "0x%02X", deviceIndex)), isCandidate=\(isHIDPPCandidate)")

        // 只对 HID++ 候选接口进行协议通信
        guard isHIDPPCandidate else {
            LogitechHIDDebugPanel.log("\(tag) Skipping: not a HID++ candidate interface")
            // 仍然注册 input report 回调以捕获广播通知 (如 SmartShift)
            setupInputReportCallback()
            return
        }

        // 显式打开设备 (IOHIDManagerOpen 可能不够)
        let openResult = IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            deviceOpened = true
            LogitechHIDDebugPanel.log("\(tag) IOHIDDeviceOpen: OK")
        } else {
            LogitechHIDDebugPanel.log("\(tag) IOHIDDeviceOpen: failed \(String(format: "0x%08x", openResult)), proceeding anyway")
        }

        setupInputReportCallback()

        // Feature Discovery
        LogitechHIDDebugPanel.log("\(tag) Starting feature discovery for REPROG_CONTROLS_V4 (0x1B04)")
        discoverFeature(featureId: Self.featureReprogV4) { [weak self] index in
            guard let self = self, let index = index else {
                LogitechHIDDebugPanel.log("\(tag) REPROG_CONTROLS_V4 not available")
                return
            }
            self.featureIndex[Self.featureReprogV4] = index
            LogitechHIDDebugPanel.log("\(tag) REPROG_CONTROLS_V4 at index \(String(format: "0x%02X", index))")
            self.sendGetControlCount(featureIndex: index)
        }
    }

    private func setupInputReportCallback() {
        reportBufferPtr = .allocate(capacity: Self.reportBufferSize)
        reportBufferPtr!.initialize(repeating: 0, count: Self.reportBufferSize)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            hidDevice, reportBufferPtr!, Self.reportBufferSize, Self.inputReportCallback, context
        )
    }

    func teardown() {
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Teardown")
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        pendingDiscovery.removeAll()
        if let reprogIdx = featureIndex[Self.featureReprogV4] {
            for cid in divertedCIDs {
                setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
            }
        }
        divertedCIDs.removeAll()
        lastActiveCIDs.removeAll()
        discoveredControls.removeAll()
    }

    // MARK: - Input Report Callback

    static let inputReportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
        guard let context = context else { return }
        let session = Unmanaged<LogitechDeviceSession>.fromOpaque(context).takeUnretainedValue()
        let data = Array(UnsafeBufferPointer(start: report, count: reportLength))
        session.handleInputReport(data)
    }

    // MARK: - HID++ Send

    /// 发送 HID++ 请求
    /// hidapi 兼容: report ID 包含在 payload 中, 使用 long report (20 bytes)
    /// IOHIDDeviceSetReport(dev, OUTPUT, data[0], data, data.count)
    private func sendRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8] = []) {
        // 始终使用 long report (20 bytes), BLE 设备不支持 short report
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = Self.hidppLongReportId  // 0x11
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (functionId << 4) | 0x01  // FuncID | SwID
        for (i, p) in params.prefix(16).enumerated() {
            report[4 + i] = p
        }

        let hex = report.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")

        // hidapi 兼容: data 包含 report ID, length = 全长
        let result = IOHIDDeviceSetReport(
            hidDevice, kIOHIDReportTypeOutput,
            CFIndex(report[0]),  // report ID
            report,              // data (含 report ID)
            report.count         // 20 bytes
        )
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] TX: \(hex)... -> \(result == kIOReturnSuccess ? "OK" : String(format: "0x%08x", result))")
    }

    // MARK: - Feature Discovery

    private func discoverFeature(featureId: UInt16, completion: @escaping (UInt8?) -> Void) {
        let params: [UInt8] = [UInt8(featureId >> 8), UInt8(featureId & 0xFF)]
        sendRequest(featureIndex: 0x00, functionId: 0, params: params)
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

    // MARK: - REPROG_CONTROLS_V4 Flow

    private func sendGetControlCount(featureIndex: UInt8) {
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Sending GetControlCount")
        sendRequest(featureIndex: featureIndex, functionId: 0)
    }

    private func sendGetControlInfo(featureIndex: UInt8, index: Int) {
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Sending GetControlInfo(\(index))")
        sendRequest(featureIndex: featureIndex, functionId: 1, params: [UInt8(index)])
    }

    private func setControlReporting(featureIndex: UInt8, cid: UInt16, divert: Bool) {
        let flagsByte: UInt8 = divert ? 0x01 : 0x00
        sendRequest(featureIndex: featureIndex, functionId: 3,
                         params: [UInt8(cid >> 8), UInt8(cid & 0xFF), flagsByte])
        if divert { divertedCIDs.insert(cid) } else { divertedCIDs.remove(cid) }
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] CID \(String(format: "0x%04X", cid)) divert=\(divert ? "ON" : "OFF")")
    }

    // MARK: - Report Parsing

    func handleInputReport(_ report: [UInt8]) {
        guard report.count >= 7 else { return }
        guard report[0] == Self.hidppShortReportId || report[0] == Self.hidppLongReportId else { return }

        let hex = report.prefix(min(report.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] RX: \(hex)")

        let featureIdx = report[2]
        let functionId = report[3] >> 4

        // Error report
        if featureIdx == Self.hidppErrorFeatureIdx {
            let errorCode = report.count > 6 ? report[6] : 0
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] HID++ Error: feat=\(String(format: "0x%02X", report[3])) err=\(String(format: "0x%02X", errorCode))")
            for (featureId, callback) in pendingDiscovery {
                callback(nil)
                pendingDiscovery.removeValue(forKey: featureId)
            }
            return
        }

        // IRoot response
        if featureIdx == 0x00 {
            handleDiscoveryResponse(report)
            return
        }

        // REPROG_CONTROLS_V4
        if let reprogIdx = featureIndex[Self.featureReprogV4], featureIdx == reprogIdx {
            switch functionId {
            case 0: handleGetControlCountResponse(report)
            case 1: handleGetControlInfoResponse(report)
            default: handleDivertedButtonEvent(report)
            }
            return
        }
    }

    private func handleDiscoveryResponse(_ report: [UInt8]) {
        let discoveredIndex = report[4]
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] IRoot response: discoveredIndex=\(String(format: "0x%02X", discoveredIndex))")
        if let (featureId, callback) = pendingDiscovery.first {
            discoveryTimer?.invalidate()
            pendingDiscovery.removeValue(forKey: featureId)
            callback(discoveredIndex == 0 ? nil : discoveredIndex)
        }
    }

    private func handleGetControlCountResponse(_ report: [UInt8]) {
        reprogControlCount = Int(report[4])
        reprogQueryIndex = 0
        discoveredControls.removeAll()
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] GetControlCount = \(reprogControlCount)")
        if reprogControlCount > 0, let idx = featureIndex[Self.featureReprogV4] {
            sendGetControlInfo(featureIndex: idx, index: 0)
        }
    }

    private func handleGetControlInfoResponse(_ report: [UInt8]) {
        guard report.count >= 11 else { return }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let taskId = (UInt16(report[6]) << 8) | UInt16(report[7])
        let flags1 = report[8]
        let flags2: UInt8 = report.count > 12 ? report[12] : 0
        let flags = UInt16(flags1) | (UInt16(flags2) << 8)
        let isDivertable = (flags & 0x08) != 0

        discoveredControls.append(ControlInfo(cid: cid, taskId: taskId, flags: flags, isDivertable: isDivertable))
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Control[\(reprogQueryIndex)]: CID=\(String(format: "0x%04X", cid)) flags=\(String(format: "0x%04X", flags)) divertable=\(isDivertable)")

        reprogQueryIndex += 1
        if reprogQueryIndex < reprogControlCount, let idx = featureIndex[Self.featureReprogV4] {
            sendGetControlInfo(featureIndex: idx, index: reprogQueryIndex)
        } else {
            divertAllControls()
        }
    }

    private func divertAllControls() {
        guard let idx = featureIndex[Self.featureReprogV4] else { return }
        let divertable = discoveredControls.filter { $0.isDivertable }
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Diverting \(divertable.count)/\(discoveredControls.count) controls")
        for c in divertable {
            setControlReporting(featureIndex: idx, cid: c.cid, divert: true)
        }
    }

    private func handleDivertedButtonEvent(_ report: [UInt8]) {
        var activeCIDs: Set<UInt16> = []
        var offset = 4
        while offset + 1 < report.count {
            let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
            if cid == 0 { break }
            activeCIDs.insert(cid)
            offset += 2
        }
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
