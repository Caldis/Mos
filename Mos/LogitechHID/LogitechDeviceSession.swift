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

    // MARK: - Report Buffer
    // 必须用堆指针, Swift Array 是 value type, copy-on-write 时地址会变
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private static let reportBufferSize = 64

    // MARK: - Async Discovery
    private var pendingDiscovery: [UInt16: (UInt8?) -> Void] = [:]
    private var discoveryTimer: Timer?
    private static let discoveryTimeout: TimeInterval = 5.0

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
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Setting up session (usagePage: \(String(format: "0x%04X", usagePage)), usage: \(String(format: "0x%04X", usage)))")

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
            self.queryAndDivertButtons(featureIndex: index)
        }
    }

    func teardown() {
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Tearing down session")
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        pendingDiscovery.removeAll()

        // 取消 divert (恢复按键的默认行为)
        if let reprogIdx = featureIndex[Self.featureReprogV4] {
            for cid in divertedCIDs {
                setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
            }
        }
        divertedCIDs.removeAll()
        lastActiveCIDs.removeAll()
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

        let result = IOHIDDeviceSetReport(
            hidDevice,
            kIOHIDReportTypeOutput,
            CFIndex(report[0]),
            report,
            report.count
        )
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

    // MARK: - Button Divert

    private func queryAndDivertButtons(featureIndex: UInt8) {
        // GetControlCount: function 0
        sendShortRequest(featureIndex: featureIndex, functionId: 0)
        // 响应在 handleInputReport 中处理
    }

    private func setControlReporting(featureIndex: UInt8, cid: UInt16, divert: Bool) {
        // SetControlReporting: function 3
        let flags: UInt8 = divert ? 0x01 : 0x00
        let params: [UInt8] = [UInt8(cid >> 8), UInt8(cid & 0xFF), flags]
        sendShortRequest(featureIndex: featureIndex, functionId: 3, params: params)
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

        // Error report
        if featureIdx == Self.hidppErrorFeatureIdx {
            let errorCode = report.count > 6 ? report[6] : 0
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Error report: featureIdx=\(String(format: "0x%02X", report[3])) errorCode=\(String(format: "0x%02X", errorCode))")
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

        // REPROG_CONTROLS_V4 events
        if let reprogIdx = featureIndex[Self.featureReprogV4], featureIdx == reprogIdx {
            handleReprogEvent(report)
            return
        }
    }

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

    private func handleReprogEvent(_ report: [UInt8]) {
        // Parse CID pairs from divertedButtonsEvent notification
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

        // 处理事件
        let _ = MosInputProcessor.shared.process(mosEvent)

        // 发送通知 (供 KeyRecorder 录制监听)
        NotificationCenter.default.post(
            name: LogitechHIDManager.buttonEventNotification,
            object: nil,
            userInfo: ["event": mosEvent]
        )
    }
}
