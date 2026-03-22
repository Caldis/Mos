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

    // MARK: - Connection Mode
    /// 连接模式: 决定传输格式、device index 策略、divert flags
    enum ConnectionMode {
        /// BLE 直连: long report + ID in payload, devIdx=0xFF, divert flags=0x03
        case bleDirect
        /// USB Receiver (Unifying/Bolt): vendor-specific interface, devIdx=slot(0x01~0x06)
        /// TODO: 需要实现槽位发现 (HID++ 1.0 枚举配对设备)
        case receiver
        /// 未知/不支持
        case unsupported
    }

    private(set) var connectionMode: ConnectionMode = .unsupported

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
    private var pendingCacheValidation: UInt8? = nil  // 等待 ping 响应验证缓存

    // MARK: - Reprog Controls State
    private var reprogControlCount: Int = 0
    private var reprogQueryIndex: Int = 0
    private var discoveredControls: [ControlInfo] = []
    private var reprogInitComplete: Bool = false  // init 完成后, function 0 = button event 而非 GetControlCount

    struct ControlInfo {
        let cid: UInt16
        let taskId: UInt16
        let flags: UInt16
        let isDivertable: Bool
    }

    // MARK: - Feature Index Cache (按 PID 缓存, 减少重连 discovery 延迟)
    private static let featureCacheKey = "logitechFeatureCache"

    private static func loadCachedFeatureIndex(for productId: UInt16) -> [UInt16: UInt8]? {
        guard let data = UserDefaults.standard.data(forKey: featureCacheKey),
              let cache = try? JSONDecoder().decode([UInt16: [UInt16: UInt8]].self, from: data) else { return nil }
        return cache[productId]
    }

    private static func saveCachedFeatureIndex(for productId: UInt16, featureMap: [UInt16: UInt8]) {
        var cache: [UInt16: [UInt16: UInt8]] = [:]
        if let data = UserDefaults.standard.data(forKey: featureCacheKey),
           let existing = try? JSONDecoder().decode([UInt16: [UInt16: UInt8]].self, from: data) {
            cache = existing
        }
        cache[productId] = featureMap
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: featureCacheKey)
        }
    }

    // MARK: - HID++ Constants
    private static let featureIRoot: UInt16 = 0x0000
    private static let featureReprogV4: UInt16 = 0x1B04
    private static let featureHiResWheel: UInt16 = 0x2121
    private static let featureThumbWheel: UInt16 = 0x2150
    private static let featurePointerSpeed: UInt16 = 0x2205
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

    // MARK: - Debug Accessors (for HID++ debug panel)
    var debugFeatureIndex: [UInt16: UInt8] { featureIndex }
    var debugDiscoveredControls: [ControlInfo] { discoveredControls }
    var debugDivertedCIDs: Set<UInt16> { divertedCIDs }
    var debugReprogInitComplete: Bool { reprogInitComplete }
    var debugDeviceIndex: UInt8 { deviceIndex }
    var debugIsBLE: Bool { isBLE }
    var debugDeviceOpened: Bool { deviceOpened }
    var debugConnectionMode: String {
        switch connectionMode {
        case .bleDirect: return "BLE Direct"
        case .receiver: return "Receiver (Unifying/Bolt)"
        case .unsupported: return "Unsupported"
        }
    }

    // MARK: - Setup / Teardown

    func setup() {
        isBLE = transport.lowercased().contains("bluetooth")

        // 确定连接模式
        if isBLE {
            connectionMode = .bleDirect
            deviceIndex = 0xFF
        } else if usagePage == 0xFF00 || usagePage == 0xFF43 || usagePage == 0xFFC0 {
            connectionMode = .receiver
            deviceIndex = 0x01  // TODO: 通过 HID++ 1.0 枚举槽位确定实际 index
        } else {
            connectionMode = .unsupported
        }

        let tag = "[\(deviceInfo.name):\(String(format: "0x%04X", usagePage))/\(String(format: "0x%04X", usage))]"
        LogitechHIDDebugPanel.log("\(tag) Setup: transport=\(transport), mode=\(connectionMode), devIdx=\(String(format: "0x%02X", deviceIndex)), isCandidate=\(isHIDPPCandidate)")

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

        // Feature Discovery (尝试缓存, 失败则完整 discovery)
        if let cached = Self.loadCachedFeatureIndex(for: deviceInfo.productId),
           let reprogIdx = cached[Self.featureReprogV4] {
            LogitechHIDDebugPanel.log("\(tag) Using cached feature index: REPROG at 0x\(String(format: "%02X", reprogIdx))")
            self.featureIndex = cached.reduce(into: [UInt16: UInt8]()) { $0[$1.key] = $1.value }
            // 用 ping 验证缓存是否有效 (IRoot.GetProtocolVersion)
            sendRequest(featureIndex: 0x00, functionId: 1)
            pendingCacheValidation = reprogIdx
        } else {
            LogitechHIDDebugPanel.log("\(tag) Starting feature discovery for REPROG_CONTROLS_V4 (0x1B04)")
            startFreshDiscovery(tag: tag)
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
        // 清理 ScrollCore 的 HID 热键状态, 防止设备断连时按键卡住
        // (设备断连后 key-up 永不会触发, 滚动热键状态会永久卡死)
        for cid in lastActiveCIDs {
            let mosCode = LogitechCIDRegistry.toMosCode(cid)
            ScrollCore.shared.handleScrollHotkeyFromHIDPlusPlus(code: mosCode, isDown: false)
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
    /// BLE 直连: long report (20 bytes) + report ID in payload (hidapi 兼容)
    /// Receiver: TODO - 可能需要不同格式, 待 Bolt/Unifying 测试后实现
    private func sendRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8] = []) {
        var report: [UInt8]
        let result: IOReturn

        switch connectionMode {
        case .bleDirect:
            // BLE: long report, hidapi 兼容 (report ID in payload)
            report = [UInt8](repeating: 0, count: 20)
            report[0] = Self.hidppLongReportId
            report[1] = deviceIndex
            report[2] = featureIndex
            report[3] = (functionId << 4) | 0x01
            for (i, p) in params.prefix(16).enumerated() { report[4 + i] = p }
            result = IOHIDDeviceSetReport(
                hidDevice, kIOHIDReportTypeOutput,
                CFIndex(report[0]), report, report.count
            )

        case .receiver:
            // TODO: Unifying/Bolt receiver 传输
            // 可能需要: short report (7 bytes), 不同的 payload 格式
            // 需要先实现 HID++ 1.0 槽位枚举
            report = [UInt8](repeating: 0, count: 20)
            report[0] = Self.hidppLongReportId
            report[1] = deviceIndex
            report[2] = featureIndex
            report[3] = (functionId << 4) | 0x01
            for (i, p) in params.prefix(16).enumerated() { report[4 + i] = p }
            result = IOHIDDeviceSetReport(
                hidDevice, kIOHIDReportTypeOutput,
                CFIndex(report[0]), report, report.count
            )

        case .unsupported:
            LogitechHIDDebugPanel.log(device: deviceInfo.name, type: .warning, message: "Cannot send: unsupported connection mode")
            return
        }

        let hex = report.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        let resultStr = result == kIOReturnSuccess ? "OK" : String(format: "0x%08x", result)
        let decoded = decodeRequest(featureIndex: featureIndex, functionId: functionId, params: params)
        LogitechHIDDebugPanel.log(device: deviceInfo.name, type: .tx, message: "TX: \(hex)... -> \(resultStr)", decoded: decoded)
    }

    // MARK: - Feature Discovery

    private func startFreshDiscovery(tag: String) {
        discoverFeature(featureId: Self.featureReprogV4) { [weak self] index in
            guard let self = self, let index = index else {
                LogitechHIDDebugPanel.log("\(tag) REPROG_CONTROLS_V4 not available")
                return
            }
            self.featureIndex[Self.featureReprogV4] = index
            LogitechHIDDebugPanel.log("\(tag) REPROG_CONTROLS_V4 at index \(String(format: "0x%02X", index))")
            // 缓存 feature index
            Self.saveCachedFeatureIndex(for: self.deviceInfo.productId, featureMap: self.featureIndex)
            self.sendGetControlCount(featureIndex: index)
        }
    }

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
        let cidH = UInt8(cid >> 8)
        let cidL = UInt8(cid & 0xFF)

        let flagsByte: UInt8
        switch connectionMode {
        case .bleDirect:
            // BLE: bit1 是 "commit" 标志, 必须置位才能生效
            // SET: bit0=1(divert ON) + bit1=1(commit) = 0x03
            // CLEAR: bit0=0(divert OFF) + bit1=1(commit) = 0x02
            flagsByte = divert ? 0x03 : 0x02
        case .receiver:
            // Receiver (Unifying/Bolt): TODO - 可能只需 tmpDiverted(bit0) = 0x01
            flagsByte = divert ? 0x01 : 0x00
        case .unsupported:
            return
        }

        // params: CID(2) + flags(1) + targetCID(2) (自映射)
        sendRequest(featureIndex: featureIndex, functionId: 3,
                         params: [cidH, cidL, flagsByte, cidH, cidL])
        if divert { divertedCIDs.insert(cid) } else { divertedCIDs.remove(cid) }
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] CID \(String(format: "0x%04X", cid)) divert=\(divert ? "ON" : "OFF")")
    }

    // MARK: - Debug Operations (interactive divert control)

    func rediscoverFeatures() {
        featureIndex.removeAll()
        discoveredControls.removeAll()
        reprogInitComplete = false
        reprogControlCount = 0
        reprogQueryIndex = 0
        divertedCIDs.removeAll()
        lastActiveCIDs.removeAll()
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Re-discovering features...")
        discoverFeature(featureId: Self.featureReprogV4) { [weak self] index in
            guard let self = self, let index = index else {
                LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] REPROG_CONTROLS_V4 not available")
                return
            }
            self.featureIndex[Self.featureReprogV4] = index
            LogitechHIDDebugPanel.log("[\(self.deviceInfo.name)] REPROG_CONTROLS_V4 at index \(String(format: "0x%02X", index))")
            self.sendGetControlCount(featureIndex: index)
        }
    }

    func redivertAllControls() {
        lastActiveCIDs.removeAll()
        reprogInitComplete = true
        syncDivertWithBindings()
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Re-synced divert with bindings")
    }

    func undivertAllControls() {
        guard let idx = featureIndex[Self.featureReprogV4] else { return }
        for cid in divertedCIDs {
            setControlReporting(featureIndex: idx, cid: cid, divert: false)
        }
        reprogInitComplete = false
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Undiverted all controls")
    }

    func toggleDivert(cid: UInt16) {
        guard let idx = featureIndex[Self.featureReprogV4] else { return }
        let currentlyDiverted = divertedCIDs.contains(cid)
        setControlReporting(featureIndex: idx, cid: cid, divert: !currentlyDiverted)
    }

    // MARK: - Report Decoding (for debug panel)

    private func decodeRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) -> String {
        if featureIndex == 0x00 && functionId == 0 && params.count >= 2 {
            let featId = (UInt16(params[0]) << 8) | UInt16(params[1])
            let name = HIDPPInfo.featureNames[featId]?.0 ?? "0x\(String(format: "%04X", featId))"
            return "IRoot.GetFeature(\(name))"
        }
        if featureIndex == 0x00 && functionId == 1 {
            return "IRoot.Ping (GetProtocolVersion)"
        }
        if let reprogIdx = self.featureIndex[Self.featureReprogV4], featureIndex == reprogIdx {
            switch functionId {
            case 0: return "REPROG.GetControlCount()"
            case 1:
                let idx = params.first.map { "\($0)" } ?? "?"
                return "REPROG.GetControlInfo(index=\(idx))"
            case 3:
                if params.count >= 3 {
                    let cid = (UInt16(params[0]) << 8) | UInt16(params[1])
                    let cidName = LogitechCIDRegistry.name(forCID: cid)
                    let divert = params[2] & 0x01 != 0
                    return "REPROG.SetControlReporting(CID=\(String(format: "0x%04X", cid)) \(cidName), divert=\(divert ? "ON" : "OFF"))"
                }
                return "REPROG.SetControlReporting"
            default: return "REPROG.func\(functionId)"
            }
        }
        return "Feature[0x\(String(format: "%02X", featureIndex))].func\(functionId)"
    }

    private func decodeReport(_ report: [UInt8]) -> String {
        guard report.count >= 7 else { return "short report" }
        let featIdx = report[2]
        let funcId = report[3] >> 4

        if featIdx == Self.hidppErrorFeatureIdx {
            let errCode = report.count > 6 ? report[6] : 0
            let errName = HIDPPInfo.errorNames[errCode] ?? "0x\(String(format: "%02X", errCode))"
            return "HID++ ERROR: \(errName)"
        }
        if featIdx == 0x00 {
            if funcId == 0 {
                let idx = report[4]
                return idx == 0 ? "IRoot: feature not found" : "IRoot: feature at index 0x\(String(format: "%02X", idx))"
            }
            if funcId == 1 {
                return "IRoot: protocol \(report[4]).\(report[5])"
            }
        }
        if let reprogIdx = featureIndex[Self.featureReprogV4], featIdx == reprogIdx {
            if !reprogInitComplete && funcId == 0 {
                return "REPROG.ControlCount = \(report[4])"
            }
            if funcId == 1 {
                let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
                let name = LogitechCIDRegistry.name(forCID: cid)
                return "REPROG.ControlInfo: CID=\(String(format: "0x%04X", cid)) (\(name))"
            }
            if reprogInitComplete && funcId == 0 {
                // divertedButtonsEvent
                var cids: [String] = []
                var offset = 4
                while offset + 1 < report.count {
                    let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
                    if cid == 0 { break }
                    let name = LogitechCIDRegistry.name(forCID: cid)
                    cids.append("\(String(format: "0x%04X", cid))(\(name))")
                    offset += 2
                }
                return cids.isEmpty ? "BUTTON EVENT: all released" : "BUTTON EVENT: \(cids.joined(separator: " + "))"
            }
            if funcId == 3 {
                return "REPROG.SetControlReporting ACK"
            }
        }
        // SmartShift or other feature notifications
        if let name = findFeatureName(forIndex: featIdx) {
            return "\(name) notification (func=\(funcId))"
        }
        return "Feature[0x\(String(format: "%02X", featIdx))].func\(funcId)"
    }

    private func findFeatureName(forIndex idx: UInt8) -> String? {
        for (featId, featIdx) in featureIndex {
            if featIdx == idx {
                return HIDPPInfo.featureNames[featId]?.0
            }
        }
        return nil
    }

    // MARK: - Logi Action Execution

    private var pendingSmartShiftToggle: UInt8? = nil
    private var pendingDPICycle: (featureIndex: UInt8, direction: LogitechHIDManager.DPICycleDirection)? = nil
    private var pendingDPIListQuery: (featureIndex: UInt8, direction: LogitechHIDManager.DPICycleDirection)? = nil
    private var currentDPI: UInt16 = 0
    private var dpiSteps: [UInt16] = []  // 从设备查询, 不硬编码
    private var dpiStepSize: UInt16 = 0  // 设备报告的 DPI 步进值
    private var pendingHiResScrollToggle = false
    private var pendingScrollInvertToggle = false
    private var pendingThumbWheelToggle = false
    private var pendingPointerSpeedCycle = false

    /// SmartShift 切换
    func executeSmartShiftToggle() {
        // SmartShift feature ID = 0x2110
        let smartShiftFeatureId: UInt16 = 0x2110
        if let idx = featureIndex[smartShiftFeatureId] {
            // 已知 feature index, 直接切换
            toggleSmartShift(featureIndex: idx)
        } else {
            // 先发现 feature
            discoverFeature(featureId: smartShiftFeatureId) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] SmartShift feature not supported")
                    return
                }
                self.featureIndex[smartShiftFeatureId] = idx
                self.toggleSmartShift(featureIndex: idx)
            }
        }
    }

    private func toggleSmartShift(featureIndex: UInt8) {
        // getRatchetControlMode: function 0
        // 响应: byte[4] = wheelMode (1=freewheel, 2=ratchet)
        sendRequest(featureIndex: featureIndex, functionId: 0)
        // 响应在 handleInputReport 中处理 -> handleSmartShiftResponse
        pendingSmartShiftToggle = featureIndex
    }

    /// DPI 循环
    func executeDPICycle(direction: LogitechHIDManager.DPICycleDirection) {
        // AdjustableDPI feature ID = 0x2201
        let dpiFeatureId: UInt16 = 0x2201
        if let idx = featureIndex[dpiFeatureId] {
            cycleDPI(featureIndex: idx, direction: direction)
        } else {
            discoverFeature(featureId: dpiFeatureId) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] AdjustableDPI feature not supported")
                    return
                }
                self.featureIndex[dpiFeatureId] = idx
                self.cycleDPI(featureIndex: idx, direction: direction)
            }
        }
    }

    private func cycleDPI(featureIndex: UInt8, direction: LogitechHIDManager.DPICycleDirection) {
        if dpiSteps.isEmpty {
            // 先查询设备支持的 DPI 列表
            // getSensorDpiList: function 1, param sensorIdx=0
            // 响应: byte[4]=sensorIdx, byte[5-6]=dpiStep, byte[7-8]=dpi1, byte[9-10]=dpi2, ...
            // 如果 dpiStep > 0: 范围模式 (min~max, 步进 dpiStep)
            // 如果 dpiStep == 0: 列表中的每个值都是一个档位
            sendRequest(featureIndex: featureIndex, functionId: 1, params: [0x00])
            pendingDPIListQuery = (featureIndex, direction)
        } else {
            // 已有 DPI 列表, 直接查询当前值并切换
            // getSensorDpi: function 2, param sensorIdx=0
            sendRequest(featureIndex: featureIndex, functionId: 2, params: [0x00])
            pendingDPICycle = (featureIndex, direction)
        }
    }

    // MARK: - ChangeHost

    private var pendingHostCycle: UInt8? = nil  // feature index, 等待 getHostInfo 响应后循环

    /// 切换到指定主机 (0-based index)
    func executeChangeHost(hostIndex: UInt8) {
        let changeHostFeatureId: UInt16 = 0x1814
        if let idx = featureIndex[changeHostFeatureId] {
            switchToHost(featureIndex: idx, hostIndex: hostIndex)
        } else {
            discoverFeature(featureId: changeHostFeatureId) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] ChangeHost feature not supported")
                    return
                }
                self.featureIndex[changeHostFeatureId] = idx
                self.switchToHost(featureIndex: idx, hostIndex: hostIndex)
            }
        }
    }

    /// 循环切换主机
    func executeHostCycle() {
        let changeHostFeatureId: UInt16 = 0x1814
        if let idx = featureIndex[changeHostFeatureId] {
            // 先查询当前主机信息, 然后切换到下一个
            sendRequest(featureIndex: idx, functionId: 0)
            pendingHostCycle = idx
        } else {
            discoverFeature(featureId: changeHostFeatureId) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] ChangeHost feature not supported")
                    return
                }
                self.featureIndex[changeHostFeatureId] = idx
                self.sendRequest(featureIndex: idx, functionId: 0)
                self.pendingHostCycle = idx
            }
        }
    }

    private func switchToHost(featureIndex: UInt8, hostIndex: UInt8) {
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Switching to host \(hostIndex + 1)")
        // setHost: function 1, param = target host index (0-based)
        sendRequest(featureIndex: featureIndex, functionId: 1, params: [hostIndex])
        // 注意: 切换后设备会断开连接, session 会被清理
    }

    // MARK: - HiResWheel / ScrollInvert / ThumbWheel / PointerSpeed Actions

    /// Hi-Res 滚轮模式切换
    private func executeHiResScrollToggle() {
        if let idx = featureIndex[Self.featureHiResWheel] {
            pendingHiResScrollToggle = true
            // Get current mode (function 0x10)
            sendRequest(featureIndex: idx, functionId: 0x10, params: [])
        } else {
            discoverFeature(featureId: Self.featureHiResWheel) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] HiResScroll: feature not available")
                    return
                }
                self.featureIndex[Self.featureHiResWheel] = idx
                self.pendingHiResScrollToggle = true
                self.sendRequest(featureIndex: idx, functionId: 0x10, params: [])
            }
        }
    }

    /// 滚轮方向反转切换
    private func executeScrollInvertToggle() {
        if let idx = featureIndex[Self.featureHiResWheel] {
            pendingScrollInvertToggle = true
            // Get current mode (function 0x10)
            sendRequest(featureIndex: idx, functionId: 0x10, params: [])
        } else {
            discoverFeature(featureId: Self.featureHiResWheel) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] ScrollInvert: feature not available")
                    return
                }
                self.featureIndex[Self.featureHiResWheel] = idx
                self.pendingScrollInvertToggle = true
                self.sendRequest(featureIndex: idx, functionId: 0x10, params: [])
            }
        }
    }

    /// 拇指轮模式切换
    private func executeThumbWheelToggle() {
        if let idx = featureIndex[Self.featureThumbWheel] {
            pendingThumbWheelToggle = true
            // Get current mode (function 0x10)
            sendRequest(featureIndex: idx, functionId: 0x10, params: [])
        } else {
            discoverFeature(featureId: Self.featureThumbWheel) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] ThumbWheel: feature not available")
                    return
                }
                self.featureIndex[Self.featureThumbWheel] = idx
                self.pendingThumbWheelToggle = true
                self.sendRequest(featureIndex: idx, functionId: 0x10, params: [])
            }
        }
    }

    /// 指针速度循环 (0.5x → 1x → 1.5x → 2x → 0.5x)
    private func executePointerSpeedCycle() {
        if let idx = featureIndex[Self.featurePointerSpeed] {
            pendingPointerSpeedCycle = true
            // Get current speed (function 0x00)
            sendRequest(featureIndex: idx, functionId: 0x00, params: [])
        } else {
            discoverFeature(featureId: Self.featurePointerSpeed) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogitechHIDDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] PointerSpeed: feature not available")
                    return
                }
                self.featureIndex[Self.featurePointerSpeed] = idx
                self.pendingPointerSpeedCycle = true
                self.sendRequest(featureIndex: idx, functionId: 0x00, params: [])
            }
        }
    }

    // MARK: - Report Parsing

    func handleInputReport(_ report: [UInt8]) {
        guard report.count >= 7 else { return }
        guard report[0] == Self.hidppShortReportId || report[0] == Self.hidppLongReportId else { return }

        let hex = report.prefix(min(report.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        let featureIdx = report[2]
        let functionId = report[3] >> 4
        let rxDecoded = decodeReport(report)
        let rxType: LogEntryType = featureIdx == Self.hidppErrorFeatureIdx ? .error : .rx
        LogitechHIDDebugPanel.log(device: deviceInfo.name, type: rxType, message: "RX: \(hex)", decoded: rxDecoded)

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
            // 缓存验证: ping 响应 (function 1) 确认设备在线, 直接用缓存的 feature index
            if let reprogIdx = pendingCacheValidation, functionId == 1 {
                pendingCacheValidation = nil
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Cache validated (protocol \(report[4]).\(report[5])), using cached index 0x\(String(format: "%02X", reprogIdx))")
                sendGetControlCount(featureIndex: reprogIdx)
                return
            }
            handleDiscoveryResponse(report)
            return
        }

        // REPROG_CONTROLS_V4
        if let reprogIdx = featureIndex[Self.featureReprogV4], featureIdx == reprogIdx {
            if reprogInitComplete {
                // init 完成后: 所有 REPROG 消息都是 button event (function 0 = divertedButtonsEvent)
                if functionId == 0 {
                    handleDivertedButtonEvent(report)
                }
                // function 3 = SetControlReporting ACK, 忽略
                // function 1/2 等也忽略
            } else {
                // init 阶段: 按 function ID 路由
                switch functionId {
                case 0: handleGetControlCountResponse(report)
                case 1: handleGetControlInfoResponse(report)
                default: break  // ACK 等直接忽略, 不当作 button event
                }
            }
            return
        }

        // SmartShift response (pending toggle)
        if let smartShiftIdx = pendingSmartShiftToggle, featureIdx == smartShiftIdx && functionId == 0 {
            pendingSmartShiftToggle = nil
            let currentMode = report[4]  // 1=freewheel, 2=ratchet
            let newMode: UInt8 = (currentMode == 2) ? 1 : 2
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] SmartShift: \(currentMode == 2 ? "ratchet" : "freewheel") -> \(newMode == 2 ? "ratchet" : "freewheel")")
            // setRatchetControlMode: function 1, params: wheelMode
            sendRequest(featureIndex: smartShiftIdx, functionId: 1, params: [newMode])
            return
        }

        // DPI list response (getSensorDpiList, function 1)
        if let listQuery = pendingDPIListQuery, featureIdx == listQuery.featureIndex && functionId == 1 {
            pendingDPIListQuery = nil
            dpiSteps.removeAll()
            dpiStepSize = 0

            // 从 byte[5] 开始读取 UInt16 值序列 (byte[4]=sensorIdx)
            // Solaar 规则: 值 > 0xE000 是步进标记 (step = value - 0xE000)
            // 格式: [minDPI, 0xE000+step, maxDPI, 0x0000(end)]
            // 或: [dpi1, dpi2, dpi3, ..., 0x0000] (离散列表)
            var values: [UInt16] = []
            var step: UInt16 = 0
            var offset = 5
            while offset + 1 < report.count {
                let val = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
                if val == 0 { break }
                if val > 0xE000 {
                    step = val - 0xE000
                } else {
                    values.append(val)
                }
                offset += 2
            }

            if step > 0 && values.count >= 2 {
                // 范围模式: values[0]=min, values[1]=max
                let dpiMin = values[0]
                let dpiMax = values[1]
                dpiStepSize = step
                var dpi = dpiMin
                while dpi <= dpiMax {
                    dpiSteps.append(dpi)
                    dpi += step
                }
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] DPI range: \(dpiMin)-\(dpiMax) step \(step) (\(dpiSteps.count) levels)")
            } else {
                // 离散列表模式
                dpiSteps = values
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] DPI list: \(dpiSteps)")
            }

            // 继续: 查询当前 DPI 并执行切换
            sendRequest(featureIndex: listQuery.featureIndex, functionId: 2, params: [0x00])
            pendingDPICycle = (listQuery.featureIndex, listQuery.direction)
            return
        }

        // DPI response (pending cycle)
        if let dpiInfo = pendingDPICycle, featureIdx == dpiInfo.featureIndex && functionId == 2 {
            pendingDPICycle = nil
            // byte[4]=sensorIdx, byte[5-6]=currentDPI (big-endian)
            let curDPI = (UInt16(report[5]) << 8) | UInt16(report[6])
            currentDPI = curDPI

            // Find next/prev DPI step
            let sortedSteps = dpiSteps.sorted()
            let newDPI: UInt16
            if dpiInfo.direction == .up {
                newDPI = sortedSteps.first(where: { $0 > curDPI }) ?? sortedSteps.last ?? curDPI
            } else {
                newDPI = sortedSteps.last(where: { $0 < curDPI }) ?? sortedSteps.first ?? curDPI
            }

            if newDPI != curDPI {
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] DPI: \(curDPI) -> \(newDPI)")
                // setSensorDpi: function 3, params: sensorIdx(1) + dpi(2)
                sendRequest(featureIndex: dpiInfo.featureIndex, functionId: 3, params: [0x00, UInt8(newDPI >> 8), UInt8(newDPI & 0xFF)])
            } else {
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] DPI: \(curDPI) (already at limit)")
            }
            return
        }

        // ChangeHost response (getHostInfo, function 0) - 用于 cycle
        if let hostIdx = pendingHostCycle, featureIdx == hostIdx && functionId == 0 {
            pendingHostCycle = nil
            let hostCount = report[4]
            let currentHost = report[5]
            let nextHost = (currentHost + 1) % hostCount
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Host: \(currentHost + 1)/\(hostCount) -> \(nextHost + 1)")
            switchToHost(featureIndex: hostIdx, hostIndex: nextHost)
            return
        }

        // HiResWheel response (pending HiRes toggle or ScrollInvert toggle)
        if let hiresIdx = featureIndex[Self.featureHiResWheel], featureIdx == hiresIdx {
            if pendingHiResScrollToggle && functionId == 1 {  // response to function 0x10 (0x10 >> 4 = 1)
                let currentMode = report[4]
                let newMode = currentMode ^ 0x02  // Toggle bit 1 (resolution)
                sendRequest(featureIndex: hiresIdx, functionId: 0x20, params: [newMode])
                pendingHiResScrollToggle = false
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] HiResScroll: \((newMode & 0x02) != 0 ? "ON" : "OFF")")
                return
            }
            if pendingScrollInvertToggle && functionId == 1 {  // response to function 0x10 (0x10 >> 4 = 1)
                let currentMode = report[4]
                let newMode = currentMode ^ 0x04  // Toggle bit 2 (invert)
                sendRequest(featureIndex: hiresIdx, functionId: 0x20, params: [newMode])
                pendingScrollInvertToggle = false
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] ScrollInvert: \((newMode & 0x04) != 0 ? "ON" : "OFF")")
                return
            }
        }

        // ThumbWheel response
        if let thumbIdx = featureIndex[Self.featureThumbWheel], featureIdx == thumbIdx {
            if pendingThumbWheelToggle && functionId == 1 {  // response to function 0x10 (0x10 >> 4 = 1)
                let byte1 = report[4]
                let byte2 = report[5]
                let newByte1 = byte1 ^ 0x01  // Toggle bit 0 (divert mode)
                sendRequest(featureIndex: thumbIdx, functionId: 0x20, params: [newByte1, byte2])
                pendingThumbWheelToggle = false
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] ThumbWheel: \((newByte1 & 0x01) != 0 ? "DIVERT" : "NORMAL")")
                return
            }
        }

        // PointerSpeed response
        if let speedIdx = featureIndex[Self.featurePointerSpeed], featureIdx == speedIdx {
            if pendingPointerSpeedCycle && functionId == 0 {  // response to function 0x00 (0x00 >> 4 = 0)
                let currentHi = report[4]
                let currentLo = report[5]
                let currentSpeed = (UInt16(currentHi) << 8) | UInt16(currentLo)

                // Cycle through presets: 0.5x(128) → 1x(256) → 1.5x(384) → 2x(512→clamped to 511) → 0.5x
                let presets: [UInt16] = [0x0080, 0x0100, 0x0180, 0x01FF]
                let nextSpeed: UInt16
                if let idx = presets.firstIndex(where: { $0 > currentSpeed }) {
                    nextSpeed = presets[idx]
                } else {
                    nextSpeed = presets[0]  // Wrap around to 0.5x
                }

                sendRequest(featureIndex: speedIdx, functionId: 0x10,
                            params: [UInt8(nextSpeed >> 8), UInt8(nextSpeed & 0xFF)])
                pendingPointerSpeedCycle = false
                let speedStr = String(format: "%.1fx", Double(nextSpeed) / 256.0)
                LogitechHIDDebugPanel.log("[\(deviceInfo.name)] PointerSpeed: \(speedStr)")
                return
            }
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
        // Solaar: bit 4 = reprogrammable (0x10), bit 5 = divertable (0x20)
        let isDivertable = (flags & 0x20) != 0

        discoveredControls.append(ControlInfo(cid: cid, taskId: taskId, flags: flags, isDivertable: isDivertable))
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Control[\(reprogQueryIndex)]: CID=\(String(format: "0x%04X", cid)) flags=\(String(format: "0x%04X", flags)) divertable=\(isDivertable)")

        reprogQueryIndex += 1
        if reprogQueryIndex < reprogControlCount, let idx = featureIndex[Self.featureReprogV4] {
            sendGetControlInfo(featureIndex: idx, index: reprogQueryIndex)
        } else {
            divertBoundControls()
        }
    }

    /// 初始化完成后: 清理 persistDivert 残留, 然后按 binding 重新 divert
    private func divertBoundControls() {
        guard let idx = featureIndex[Self.featureReprogV4] else { return }

        // 先 undivert 所有 divertable 控件 (清理 app 崩溃/强杀后的 persistDivert 残留)
        let divertable = discoveredControls.filter { $0.isDivertable }
        for c in divertable {
            setControlReporting(featureIndex: idx, cid: c.cid, divert: false)
        }
        divertedCIDs.removeAll()
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Cleared persistDivert residue (\(divertable.count) controls)")

        // 再按 binding 状态重新 divert
        reprogInitComplete = true
        lastActiveCIDs.removeAll()
        syncDivertWithBindings()
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Init complete, listening for button events")
    }

    /// 同步 divert 状态: 只 divert 有绑定的按键, un-divert 没有绑定的
    func syncDivertWithBindings() {
        guard let idx = featureIndex[Self.featureReprogV4] else { return }

        // 收集所有需要 divert 的 Logi 鼠标按键码
        var boundCodes = Set<UInt16>()

        // 1. 按键面板: 全局按钮绑定
        for binding in ButtonUtils.shared.getButtonBindings() where binding.isEnabled && binding.triggerEvent.type == .mouse {
            boundCodes.insert(binding.triggerEvent.code)
        }

        // 2. 滚动面板: 全局滚动热键 (dash/toggle/block)
        for hotkey in [Options.shared.scroll.dash, Options.shared.scroll.toggle, Options.shared.scroll.block] {
            if let h = hotkey, h.type == .mouse, LogitechCIDRegistry.isLogitechCode(h.code) {
                boundCodes.insert(h.code)
            }
        }

        // 3. 应用程序面板: 分应用滚动热键 (非继承的应用)
        let apps = Options.shared.application.applications
        for i in 0..<apps.count {
            guard let app = apps.get(by: i), !app.inherit else { continue }
            for hotkey in [app.scroll.dash, app.scroll.toggle, app.scroll.block] {
                if let h = hotkey, h.type == .mouse, LogitechCIDRegistry.isLogitechCode(h.code) {
                    boundCodes.insert(h.code)
                }
            }
        }

        let divertable = discoveredControls.filter { $0.isDivertable }
        var divertCount = 0

        for c in divertable {
            let mosCode = LogitechCIDRegistry.toMosCode(c.cid)
            let shouldDivert = boundCodes.contains(mosCode)
            let currentlyDiverted = divertedCIDs.contains(c.cid)

            if shouldDivert && !currentlyDiverted {
                setControlReporting(featureIndex: idx, cid: c.cid, divert: true)
                divertCount += 1
            } else if !shouldDivert && currentlyDiverted {
                setControlReporting(featureIndex: idx, cid: c.cid, divert: false)
            } else if shouldDivert {
                divertCount += 1
            }
        }

        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Sync divert: \(divertCount)/\(divertable.count) controls diverted (based on bindings)")
    }

    /// 录制模式: 临时 divert 所有 divertable 按键
    func temporarilyDivertAll() {
        guard let idx = featureIndex[Self.featureReprogV4] else { return }
        let divertable = discoveredControls.filter { $0.isDivertable }
        for c in divertable where !divertedCIDs.contains(c.cid) {
            setControlReporting(featureIndex: idx, cid: c.cid, divert: true)
        }
        LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Temporarily diverted all \(divertable.count) controls (recording mode)")
    }

    /// 录制结束: 恢复到只 divert 有绑定的状态
    func restoreDivertToBindings() {
        syncDivertWithBindings()
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
            let cidName = LogitechCIDRegistry.name(forCID: cid)
            LogitechHIDDebugPanel.log(device: deviceInfo.name, type: .buttonEvent, message: "Button DOWN: CID \(String(format: "0x%04X", cid)) (\(cidName))")
            dispatchButtonEvent(cid: cid, isDown: true)
        }
        for cid in newlyReleased {
            let cidName = LogitechCIDRegistry.name(forCID: cid)
            LogitechHIDDebugPanel.log(device: deviceInfo.name, type: .buttonEvent, message: "Button UP: CID \(String(format: "0x%04X", cid)) (\(cidName))")
            dispatchButtonEvent(cid: cid, isDown: false)
        }
    }

    // MARK: - Event Dispatch

    private func dispatchButtonEvent(cid: UInt16, isDown: Bool) {
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)
        let mosEvent = MosInputEvent(
            type: .mouse,
            code: LogitechCIDRegistry.toMosCode(cid),
            modifiers: currentFlags,
            phase: isDown ? .down : .up,
            source: .hidPlusPlus,
            device: deviceInfo
        )

        // 录制模式: 不执行动作, 只转发给 KeyRecorder
        if LogitechHIDManager.shared.isRecording {
            NotificationCenter.default.post(
                name: LogitechHIDManager.buttonEventNotification,
                object: nil,
                userInfo: ["event": mosEvent]
            )
            return
        }

        // 匹配滚动热键 (dash/toggle/block)
        // HID++ 事件不经过 CGEventTap, 需要在此处单独处理
        // 注意: 不做 early return, 允许同一按键同时触发滚动热键和按钮绑定
        ScrollCore.shared.handleScrollHotkeyFromHIDPlusPlus(
            code: mosEvent.code, isDown: isDown
        )

        // 匹配 binding, 如果是 logi* 动作则在当前 session 执行 (设备隔离)
        if isDown {
            let bindings = ButtonUtils.shared.getButtonBindings()
            if let binding = bindings.first(where: { $0.triggerEvent.matchesMosInput(mosEvent) && $0.isEnabled }) {
                if binding.systemShortcutName.hasPrefix("logi") {
                    executeLogiAction(binding.systemShortcutName)
                } else {
                    ShortcutExecutor.shared.execute(named: binding.systemShortcutName)
                }
                return
            }
        }

        // 未匹配的事件走 MosInputProcessor
        let _ = MosInputProcessor.shared.process(mosEvent)

        // 通知 KeyRecorder
        NotificationCenter.default.post(
            name: LogitechHIDManager.buttonEventNotification,
            object: nil,
            userInfo: ["event": mosEvent]
        )
    }

    /// 在当前 session 上执行 Logi 动作
    private func executeLogiAction(_ name: String) {
        switch name {
        case "logiSmartShiftToggle":
            executeSmartShiftToggle()
        case "logiDPICycleUp":
            executeDPICycle(direction: .up)
        case "logiDPICycleDown":
            executeDPICycle(direction: .down)
        case "logiHost1":
            executeChangeHost(hostIndex: 0)
        case "logiHost2":
            executeChangeHost(hostIndex: 1)
        case "logiHost3":
            executeChangeHost(hostIndex: 2)
        case "logiHiResScrollToggle":
            executeHiResScrollToggle()
        case "logiScrollInvertToggle":
            executeScrollInvertToggle()
        case "logiThumbWheelToggle":
            executeThumbWheelToggle()
        case "logiPointerSpeedCycle":
            executePointerSpeedCycle()
        default:
            LogitechHIDDebugPanel.log("[\(deviceInfo.name)] Unknown Logi action: \(name)")
        }
    }
}
