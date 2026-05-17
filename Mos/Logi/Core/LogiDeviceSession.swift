//
//  LogiDeviceSession.swift
//  Mos
//  单个 Logitech 设备的 HID++ 2.0 通信会话
//  实现 Feature Discovery, Button Divert, 事件解析
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import IOKit
import IOKit.hid

struct LogiButtonStateDelta: Equatable {
    let pressed: Set<UInt16>
    let released: Set<UInt16>
}

struct LogiButtonStateTracker {
    private(set) var activeCIDs: Set<UInt16> = []

    mutating func update(activeCIDs newActiveCIDs: Set<UInt16>) -> LogiButtonStateDelta {
        let delta = LogiButtonStateDelta(
            pressed: newActiveCIDs.subtracting(activeCIDs),
            released: activeCIDs.subtracting(newActiveCIDs)
        )
        activeCIDs = newActiveCIDs
        return delta
    }

    mutating func releaseActiveCIDs(in cids: Set<UInt16>) -> Set<UInt16> {
        let released = activeCIDs.intersection(cids)
        activeCIDs.subtract(released)
        return released
    }

    mutating func releaseAll() -> Set<UInt16> {
        let released = activeCIDs
        activeCIDs.removeAll()
        return released
    }
}

class LogiDeviceSession {

    // MARK: - Public
    let hidDevice: IOHIDDevice
    let deviceInfo: InputDevice
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

    enum ReceiverReconnectAction: Equatable {
        case ignore
        case refreshReporting
        case rediscoverFeatures
    }

    enum ReceiverConnectionNotificationAction: Equatable {
        case ignore
        case currentTargetConnected
        case currentTargetDisconnected
        case retarget(UInt8)

        var debugLabel: String {
            switch self {
            case .ignore:
                return "ignore"
            case .currentTargetConnected:
                return "currentTargetConnected"
            case .currentTargetDisconnected:
                return "currentTargetDisconnected"
            case .retarget(let slot):
                return "retarget(\(slot))"
            }
        }
    }

    // MARK: - HID++ State
    private var featureIndex: [UInt16: UInt8] = [:]
    private var divertedCIDs: Set<UInt16> = []
    private var buttonStateTracker = LogiButtonStateTracker()
    private var deviceIndex: UInt8 = 0x01
    private var isBLE: Bool = false
    private var deviceOpened: Bool = false

    // MARK: - Receiver Enumeration State
    private(set) var receiverPairedDevices: [ReceiverPairedDevice] = []
    private var pendingSlotPings: Set<UInt8> = []
    private var receiverEnumPhase: Int = 0  // 0=idle, 1=pinging, 2=querying info

    // MARK: - Report Buffer
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private static let reportBufferSize = 64

    // MARK: - Async Discovery
    private var pendingDiscovery: [UInt16: (UInt8?) -> Void] = [:]
    private var discoveryTimer: Timer?
    private static let discoveryTimeout: TimeInterval = 5.0
    private var pendingCacheValidation: UInt8? = nil  // 等待 ping 响应验证缓存

    // MARK: - Query Timeouts (防止 Bolt receiver 上 HID++ 响应丢包 / 错误导致 query 链路卡死)
    private var controlInfoQueryTimer: Timer?
    private var reportingQueryTimer: Timer?
    private static let reprogQueryTimeout: TimeInterval = 1.0
    private static let bleControlInfoRetryLimit = 1
    private var controlInfoRetryCounts: [Int: Int] = [:]

    // MARK: - Reprog Controls State
    private var reprogControlCount: Int = 0
    private var reprogQueryIndex: Int = 0
    private var discoveredControls: [ControlInfo] = []
    private var reprogInitComplete: Bool = false  // init 完成后, function 0 = button event 而非 GetControlCount
    private var reportingQueryIndex: Int = 0      // GetControlReporting 逐按键查询进度

    /// 握手终态: receiver 枚举完成 / direct 设备 discovery 走到终点(成功或失败).
    /// sidebar 圆点据此判定 Ready vs Initializing; 与 reprogInitComplete 不同 —— 后者不覆盖
    /// "REPROG 不可用"/"GetControlCount=0" 等 discovery 失败分支.
    private var handshakeComplete: Bool = false

    /// 当前是否正在进行 discovery 握手 (setTargetSlot/rediscoverFeatures 触发, 完成/失败后清零).
    /// UI 据此显示 spinner; 和 handshakeComplete 不同 —— 前者表达"飞行中", 后者表达"终态达成".
    private var discoveryInFlight: Bool = false

    struct ControlInfo {
        let cid: UInt16
        let taskId: UInt16
        let flags: UInt16
        let isDivertable: Bool
        // GetControlReporting 查询结果
        var reportingFlags: UInt8 = 0   // bit0=tmpDivert, bit1=persistDivert, bit2=tmpRemap, bit3=persistRemap
        var targetCID: UInt16 = 0       // remap 目标 CID (0 = 自映射)
        var reportingQueried: Bool = false
    }

    struct QueriedControlState {
        let cid: UInt16
        let reportingFlags: UInt8
        let reportingQueried: Bool
    }

    enum ReprogInitFunction0Route: Equatable {
        case divertedButtonEvent
        case getControlCountResponse
        case ignored
    }

    // MARK: - Receiver Paired Device Info
    struct ReceiverPairedDevice {
        let slot: UInt8              // 1-6
        var isConnected: Bool = false
        var protocolMajor: UInt8 = 0
        var protocolMinor: UInt8 = 0
        var wirelessPID: UInt16 = 0
        var deviceType: UInt8 = 0
        var name: String = ""
        var lastError: String? = nil

        var protocolVersion: String {
            guard isConnected else { return "--" }
            return "\(protocolMajor).\(protocolMinor)"
        }

        var deviceTypeName: String {
            switch deviceType {
            case 0x01: return "Keyboard"
            case 0x02: return "Mouse"
            case 0x03: return "Numpad"
            case 0x04: return "Presenter"
            case 0x08: return "Trackball"
            case 0x09: return "Touchpad"
            default: return deviceType == 0 ? "--" : "0x\(String(format: "%02X", deviceType))"
            }
        }
    }

    // MARK: - Feature Index Cache (按 PID 缓存, 减少重连 discovery 延迟)
    private static let featureCacheKey = "logitechFeatureCache"

    #if DEBUG
    internal static var featureCacheKeyForTests: String { return featureCacheKey }
    #endif

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

    // HID++ 1.0 sub-IDs (receiver register access)
    private static let hidpp10GetRegister: UInt8 = 0x81
    private static let hidpp10GetLongRegister: UInt8 = 0x83
    private static let hidpp10ErrorMsg: UInt8 = 0x8F
    private static let hidpp10DeviceConnection: UInt8 = 0x41

    // Receiver registers
    private static let receiverPairingInfo: UInt8 = 0xB5
    private static let pairingInfoDeviceInfo: UInt8 = 0x20
    private static let pairingInfoDeviceName: UInt8 = 0x40

    private struct ReportingResponse {
        let cid: UInt16
        let reportingFlags: UInt8
        let targetCID: UInt16
    }

    private struct SetControlReportingAck {
        let cid: UInt16
        let flagsByte: UInt8
        let targetCID: UInt16

        var updatesTemporaryDivert: Bool { (flagsByte & 0x02) != 0 }
        var temporaryDivertEnabled: Bool { (flagsByte & 0x01) != 0 }
    }

    private struct PendingSetControlReportingAck {
        let flagsByte: UInt8
        let targetCID: UInt16
        let expiresAt: Date
    }

    private struct PendingControlReportingQuery {
        let sentAt: Date
        let expiresAt: Date
    }

    private static let pendingSetControlReportingAckTTL: TimeInterval = 2.0
    private static let controlReportingQueryTTL: TimeInterval = 2.0
    private static let divertReassertionDelay: TimeInterval = 0.05

    // MARK: - Init

    init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
        self.usagePage = IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        self.usage = IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        self.transport = IOHIDDeviceGetProperty(hidDevice, kIOHIDTransportKey as CFString) as? String ?? ""
        self.deviceInfo = InputDevice(
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

    /// CID set last passed to setControlReporting. Diffed against next applyUsage's
    /// projection so we only emit setControlReporting for state changes.
    internal var lastApplied: Set<UInt16> = []
    private var pendingSetControlReportingAcks: [UInt16: PendingSetControlReportingAck] = [:]
    private var divertReassertionWorkItem: DispatchWorkItem?
    private let bleStandardButtonUndivertPlanner = LogiBLEStandardButtonUndivertPlanner()
    private var bleStandardUndivertGuardWorkItem: DispatchWorkItem?
    private var bleStandardUndivertGuardGeneration = 0
    private var bleStandardUndivertGuardTargets: Set<UInt16> = []
    private var pendingBLEUndivertGuardQueries: [UInt16: PendingControlReportingQuery] = [:]

    struct RecordingDivertPlan: Equatable {
        let desired: Set<UInt16>
        let toDivert: Set<UInt16>
        let toUndivert: Set<UInt16>
    }

    private func primeFromRegistry() {
        LogiCenter.shared.registry.primeSession(self)
    }

    internal func applyUsage(_ aggregateMosCodes: Set<UInt16>) {
        #if DEBUG
        precondition(Thread.isMainThread, "applyUsage main-thread-only")
        LogiTrace.log(
            "[Session] applyUsage enter device=\(deviceInfo.name) mode=\(connectionMode) connected=\(currentReceiverTargetIsConnected) reprogInit=\(reprogInitComplete) aggregate=\(LogiTrace.codes(aggregateMosCodes)) lastApplied=\(LogiTrace.cids(lastApplied)) diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
        // Mid-discovery guard: isHIDPPCandidate is a static vendor/product check and is true
        // throughout discovery. If a setUsage fires before divertBoundControls runs, applyUsage
        // would diff against partial discoveredControls. The post-discovery prime catches up.
        guard reprogInitComplete else {
            #if DEBUG
            LogiTrace.log("[Session] applyUsage skipped: reprogInitComplete=false", device: deviceInfo.name)
            #endif
            return
        }
        guard let reprogIdx = featureIndex[Self.featureReprogV4] else {
            #if DEBUG
            LogiTrace.log("[Session] applyUsage skipped: REPROG feature missing", device: deviceInfo.name)
            #endif
            return
        }
        guard currentReceiverTargetIsConnected else {
            #if DEBUG
            LogiTrace.log("[Session] applyUsage skipped: receiver target disconnected", device: deviceInfo.name)
            #endif
            return
        }
        // Project MosCodes -> CIDs, drop unmapped, intersect with divertable CIDs.
        let divertable = Set(discoveredControls.filter { $0.isDivertable }.map { $0.cid })
        let policy = LogiButtonDeliveryPolicy.default
        let transport = LogiTransportIdentity(connectionMode)
        #if DEBUG
        let projection = aggregateMosCodes.sorted().map { code -> String in
            let cid = LogiCIDDirectory.toCID(code) ?? LogiCIDDirectory.cid(forNativeMouseButton: code)
            let cidLabel = cid.map { String(format: "0x%04X", $0) } ?? "nil"
            let mode = cid.map { LogiSessionManager.shared.deliveryMode(for: self.ownershipKey(forCID: $0)).debugLabel } ?? "none"
            let route = cid.map { policy.shouldUseHIDPPDelivery(transport: transport, cid: $0, phase: .normal) ? "hidpp" : "native" } ?? "none"
            let isDivertable = cid.map { divertable.contains($0) } ?? false
            return "\(code)->\(cidLabel) divertable=\(isDivertable) deliveryMode=\(mode) route=\(route)"
        }.joined(separator: " | ")
        LogiTrace.log("[Session] applyUsage projection \(projection)", device: deviceInfo.name)
        #endif
        let targetCIDs = Self.targetCIDsForUsage(
            aggregateMosCodes: aggregateMosCodes,
            divertableCIDs: divertable,
            transport: transport,
            phase: .normal,
            policy: policy
        ) { cid in
            LogiSessionManager.shared.deliveryMode(for: self.ownershipKey(forCID: cid))
        }
        let nativeFirstCIDs = Self.nativeFirstCIDsForUsage(
            aggregateMosCodes: aggregateMosCodes,
            divertableCIDs: divertable,
            transport: transport,
            phase: .normal,
            policy: policy
        )
        let toDivert = targetCIDs.subtracting(self.lastApplied)
        let toUndivert = self.lastApplied.subtracting(targetCIDs).union(nativeFirstCIDs)
        #if DEBUG
        LogiTrace.log(
            "[Session] applyUsage target=\(LogiTrace.cids(targetCIDs)) nativeFirst=\(LogiTrace.cids(nativeFirstCIDs)) toDivert=\(LogiTrace.cids(toDivert)) toUndivert=\(LogiTrace.cids(toUndivert))",
            device: deviceInfo.name
        )
        #endif
        releaseActiveButtonState(for: toUndivert, reason: "usage removed")
        for cid in toDivert {
            setControlReporting(featureIndex: reprogIdx, cid: cid, divert: true)
        }
        for cid in toUndivert {
            setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
        }
        self.lastApplied = targetCIDs
        scheduleBLEStandardUndivertGuard(for: nativeFirstCIDs)
    }

    private static func targetCIDsForUsage(
        aggregateMosCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        transport: LogiTransportIdentity,
        phase: LogiButtonDeliveryPhase,
        policy: LogiButtonDeliveryPolicy,
        deliveryModeForCID: (UInt16) -> LogiButtonDeliveryMode
    ) -> Set<UInt16> {
        return aggregateMosCodes.reduce(into: Set<UInt16>()) { acc, code in
            guard let cid = LogiCIDDirectory.toCID(code),
                  divertableCIDs.contains(cid),
                  shouldUseHIDPPDelivery(mode: deliveryModeForCID(cid)),
                  policy.shouldUseHIDPPDelivery(transport: transport, cid: cid, phase: phase) else {
                return
            }
            acc.insert(cid)
        }
    }

    private static func nativeFirstCIDsForUsage(
        aggregateMosCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        transport: LogiTransportIdentity,
        phase: LogiButtonDeliveryPhase,
        policy: LogiButtonDeliveryPolicy
    ) -> Set<UInt16> {
        return aggregateMosCodes.reduce(into: Set<UInt16>()) { acc, code in
            guard let cid = LogiCIDDirectory.toCID(code) ?? LogiCIDDirectory.cid(forNativeMouseButton: code),
                  divertableCIDs.contains(cid),
                  !policy.shouldUseHIDPPDelivery(transport: transport, cid: cid, phase: phase) else {
                return
            }
            acc.insert(cid)
        }
    }

    private static func shouldUseHIDPPDelivery(mode: LogiButtonDeliveryMode) -> Bool {
        switch mode {
        case .hidpp:
            return true
        case .contended:
            return false
        }
    }

    private static func recordingDivertPlan(
        divertableCIDs: Set<UInt16>,
        lastApplied: Set<UInt16>,
        transport: LogiTransportIdentity,
        policy: LogiButtonDeliveryPolicy
    ) -> RecordingDivertPlan {
        let desired = divertableCIDs.filter { cid in
            policy.shouldUseHIDPPDelivery(
                transport: transport,
                cid: cid,
                phase: .recording
            )
        }
        let nativeFirst = divertableCIDs.filter { cid in
            !policy.shouldUseHIDPPDelivery(
                transport: transport,
                cid: cid,
                phase: .recording
            )
        }
        return RecordingDivertPlan(
            desired: desired,
            toDivert: desired.subtracting(lastApplied),
            toUndivert: lastApplied.subtracting(desired).union(nativeFirst)
        )
    }

    private func scheduleBLEStandardUndivertGuard(for nativeFirstCIDs: Set<UInt16>) {
        let policy = LogiButtonDeliveryPolicy.default
        guard policy.standardButtonUndivertGuardEnabled else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] skipped: disabled by policy", device: deviceInfo.name)
            #endif
            cancelBLEStandardUndivertGuard()
            return
        }
        guard connectionMode == .bleDirect,
              currentReceiverTargetIsConnected else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] skipped mode=\(connectionMode) connected=\(currentReceiverTargetIsConnected)", device: deviceInfo.name)
            #endif
            cancelBLEStandardUndivertGuard()
            return
        }

        let activeTargets = nativeFirstCIDs.filter { LogiCIDDirectory.nativeMouseButton(forCID: $0) != nil }
        #if DEBUG
        LogiTrace.log("[StandardButtonGuard] planning target=\(LogiTrace.cids(nativeFirstCIDs)) active=\(LogiTrace.cids(activeTargets)) existing=\(LogiTrace.cids(bleStandardUndivertGuardTargets)) interval=\(String(format: "%.2fs", policy.standardButtonUndivertGuardInterval))", device: deviceInfo.name)
        #endif
        guard activeTargets != bleStandardUndivertGuardTargets else { return }

        cancelBLEStandardUndivertGuard()
        guard !activeTargets.isEmpty else { return }

        bleStandardUndivertGuardTargets = activeTargets
        #if DEBUG
        let targets = activeTargets
            .sorted()
            .map { String(format: "0x%04X", $0) }
            .joined(separator: ", ")
        LogiDebugPanel.log("[\(deviceInfo.name)] BLE standard-button undivert guard active every \(String(format: "%.1f", policy.standardButtonUndivertGuardInterval))s for CIDs: \(targets)")
        #endif
        scheduleBLEUndivertGuardTick(
            expectedTargets: activeTargets,
            generation: bleStandardUndivertGuardGeneration,
            interval: policy.standardButtonUndivertGuardInterval
        )
    }

    private func scheduleBLEUndivertGuardTick(
        expectedTargets: Set<UInt16>,
        generation: Int,
        interval: TimeInterval
    ) {
        bleStandardUndivertGuardWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runBLEStandardUndivertGuard(
                expectedTargets: expectedTargets,
                generation: generation,
                interval: interval
            )
        }
        bleStandardUndivertGuardWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    private func runBLEStandardUndivertGuard(
        expectedTargets: Set<UInt16>,
        generation: Int,
        interval: TimeInterval
    ) {
        guard generation == bleStandardUndivertGuardGeneration,
              connectionMode == .bleDirect,
              currentReceiverTargetIsConnected else {
            #if DEBUG
            LogiTrace.log(
                "[StandardButtonGuard] tick skipped generation=\(generation) currentGeneration=\(bleStandardUndivertGuardGeneration) mode=\(connectionMode) connected=\(currentReceiverTargetIsConnected)",
                device: deviceInfo.name
            )
            #endif
            return
        }

        let policy = LogiButtonDeliveryPolicy.default
        guard policy.standardButtonUndivertGuardEnabled else {
            cancelBLEStandardUndivertGuard()
            return
        }

        let activeTargets = expectedTargets.filter { LogiCIDDirectory.nativeMouseButton(forCID: $0) != nil }
        guard !activeTargets.isEmpty else {
            cancelBLEStandardUndivertGuard()
            return
        }

        bleStandardUndivertGuardTargets = activeTargets
        sendBLEUndivertGuardReportingQueries(for: activeTargets)
        scheduleBLEUndivertGuardTick(
            expectedTargets: activeTargets,
            generation: generation,
            interval: interval
        )
    }

    private func sendBLEUndivertGuardReportingQueries(for activeTargets: Set<UInt16>) {
        guard reportingQueryTimer == nil else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] reporting query deferred: full reporting refresh in flight", device: deviceInfo.name)
            #endif
            return
        }

        expireStaleBLEUndivertGuardQueries()
        let probes = bleStandardButtonUndivertPlanner.reportingQueryProbes(
            activeTargets: activeTargets,
            reprogFeatureIndex: featureIndex[Self.featureReprogV4]
        )
        guard !probes.isEmpty else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] reporting query skipped: REPROG feature unavailable", device: deviceInfo.name)
            #endif
            return
        }

        let now = Date()
        let probesToSend = probes.filter { probe in
            guard let pending = pendingBLEUndivertGuardQueries[probe.targetCID] else {
                return true
            }
            return pending.expiresAt <= now
        }
        guard !probesToSend.isEmpty else { return }

        #if DEBUG
        let targets = probesToSend
            .map { String(format: "0x%04X", $0.targetCID) }
            .joined(separator: ", ")
        LogiTrace.log("[StandardButtonGuard] query reporting targets=\(targets)", device: deviceInfo.name)
        #endif

        for probe in probesToSend {
            pendingBLEUndivertGuardQueries[probe.targetCID] = PendingControlReportingQuery(
                sentAt: now,
                expiresAt: now.addingTimeInterval(Self.controlReportingQueryTTL)
            )
            sendRequest(
                featureIndex: probe.featureIndex,
                functionId: probe.functionId,
                params: probe.params
            )
        }
    }

    private func expireStaleBLEUndivertGuardQueries(now: Date = Date()) {
        pendingBLEUndivertGuardQueries = pendingBLEUndivertGuardQueries.filter { _, pending in
            pending.expiresAt > now
        }
    }

    #if DEBUG
    internal static func targetCIDsForUsageForTests(
        aggregateMosCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        deliveryModeForCID: (UInt16) -> LogiButtonDeliveryMode
    ) -> Set<UInt16> {
        return targetCIDsForUsage(
            aggregateMosCodes: aggregateMosCodes,
            divertableCIDs: divertableCIDs,
            transport: .receiver,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(
                standardMouseButtonsUseNativeEvents: false
            ),
            deliveryModeForCID: deliveryModeForCID
        )
    }

    internal static func targetCIDsForUsageForTests(
        aggregateMosCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        transport: LogiTransportIdentity,
        phase: LogiButtonDeliveryPhase,
        policy: LogiButtonDeliveryPolicy,
        deliveryModeForCID: (UInt16) -> LogiButtonDeliveryMode
    ) -> Set<UInt16> {
        return targetCIDsForUsage(
            aggregateMosCodes: aggregateMosCodes,
            divertableCIDs: divertableCIDs,
            transport: transport,
            phase: phase,
            policy: policy,
            deliveryModeForCID: deliveryModeForCID
        )
    }

    internal static func nativeFirstCIDsForUsageForTests(
        aggregateMosCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        transport: LogiTransportIdentity,
        phase: LogiButtonDeliveryPhase,
        policy: LogiButtonDeliveryPolicy
    ) -> Set<UInt16> {
        return nativeFirstCIDsForUsage(
            aggregateMosCodes: aggregateMosCodes,
            divertableCIDs: divertableCIDs,
            transport: transport,
            phase: phase,
            policy: policy
        )
    }

    internal static func recordingDivertPlanForTests(
        divertableCIDs: Set<UInt16>,
        lastApplied: Set<UInt16>,
        transport: LogiTransportIdentity,
        policy: LogiButtonDeliveryPolicy
    ) -> RecordingDivertPlan {
        return recordingDivertPlan(
            divertableCIDs: divertableCIDs,
            lastApplied: lastApplied,
            transport: transport,
            policy: policy
        )
    }
    #endif

    // MARK: - Debug Accessors (for HID++ debug panel)
    var debugFeatureIndex: [UInt16: UInt8] { featureIndex }
    var debugDiscoveredControls: [ControlInfo] { discoveredControls }
    var debugDivertedCIDs: Set<UInt16> { divertedCIDs }

    func ownershipKey(forCID cid: UInt16) -> LogiOwnershipKey {
        return LogiOwnershipKey(
            vendorId: deviceInfo.vendorId,
            productId: deviceInfo.productId,
            name: deviceInfo.name,
            transport: LogiTransportIdentity(connectionMode),
            cid: cid
        )
    }

    func ownershipKeysForKnownControls() -> [LogiOwnershipKey] {
        return discoveredControls.map { ownershipKey(forCID: $0.cid) }
    }

    /// 查询指定 CID 的 ControlInfo (供冲突判定等外部查询使用).
    func control(forCID cid: UInt16) -> ControlInfo? {
        return discoveredControls.first(where: { $0.cid == cid })
    }
    var debugReprogInitComplete: Bool { reprogInitComplete }
    var debugHandshakeComplete: Bool { handshakeComplete }
    var debugDiscoveryInFlight: Bool { discoveryInFlight }
    var debugIsReceiver: Bool { connectionMode == .receiver }
    var debugCurrentReceiverTargetIsConnected: Bool { currentReceiverTargetIsConnected }
    var debugDeviceIndex: UInt8 { deviceIndex }
    var debugIsBLE: Bool { isBLE }
    var debugDeviceOpened: Bool { deviceOpened }
    var debugReceiverPairedDevices: [ReceiverPairedDevice] { receiverPairedDevices }
    var debugConnectionMode: String {
        switch connectionMode {
        case .bleDirect: return "BLE Direct"
        case .receiver: return "Receiver (Unifying/Bolt)"
        case .unsupported: return "Unsupported"
        }
    }

    private var currentReceiverTargetIsConnected: Bool {
        return Self.receiverTargetIsConnected(
            connectionMode: connectionMode,
            deviceIndex: deviceIndex,
            pairedDevices: receiverPairedDevices
        )
    }

    private var currentReceiverTargetConnectionIsKnown: Bool {
        return Self.receiverTargetConnectionIsKnown(
            connectionMode: connectionMode,
            deviceIndex: deviceIndex,
            pairedDevices: receiverPairedDevices
        )
    }

    private static func receiverTargetConnectionIsKnown(
        connectionMode: ConnectionMode,
        deviceIndex: UInt8,
        pairedDevices: [ReceiverPairedDevice]
    ) -> Bool {
        guard connectionMode == .receiver else { return true }
        guard deviceIndex >= 1 && deviceIndex <= 6 else { return false }
        return pairedDevices.contains(where: { $0.slot == deviceIndex })
    }

    private static func receiverTargetIsConnected(
        connectionMode: ConnectionMode,
        deviceIndex: UInt8,
        pairedDevices: [ReceiverPairedDevice]
    ) -> Bool {
        guard connectionMode == .receiver else { return true }
        guard deviceIndex >= 1 && deviceIndex <= 6 else { return false }
        return pairedDevices.first(where: { $0.slot == deviceIndex })?.isConnected ?? true
    }

    private static func receiverReconnectAction(
        hasReprogFeature: Bool,
        discoveredControlCount: Int,
        reprogControlCount: Int,
        hasInflightWork: Bool
    ) -> ReceiverReconnectAction {
        if hasInflightWork { return .ignore }
        if hasReprogFeature,
           discoveredControlCount > 0,
           discoveredControlCount == reprogControlCount {
            return .refreshReporting
        }
        return .rediscoverFeatures
    }

    private static func receiverConnectionNotificationAction(
        currentDeviceIndex: UInt8,
        incomingDeviceIndex: UInt8,
        connected: Bool,
        currentTargetConnectionIsKnown: Bool,
        currentTargetIsConnected: Bool,
        reprogInitComplete: Bool,
        hasInflightWork: Bool
    ) -> ReceiverConnectionNotificationAction {
        guard incomingDeviceIndex >= 1 && incomingDeviceIndex <= 6 else { return .ignore }
        if incomingDeviceIndex == currentDeviceIndex {
            return connected ? .currentTargetConnected : .currentTargetDisconnected
        }
        guard connected else { return .ignore }
        let currentTargetReady = currentTargetConnectionIsKnown && currentTargetIsConnected && reprogInitComplete
        guard !currentTargetReady && !hasInflightWork else { return .ignore }
        return .retarget(incomingDeviceIndex)
    }

    #if DEBUG
    internal static func receiverTargetIsConnectedForTests(
        connectionMode: ConnectionMode,
        deviceIndex: UInt8,
        pairedDevices: [ReceiverPairedDevice]
    ) -> Bool {
        return receiverTargetIsConnected(
            connectionMode: connectionMode,
            deviceIndex: deviceIndex,
            pairedDevices: pairedDevices
        )
    }

    internal static func receiverReconnectActionForTests(
        hasReprogFeature: Bool,
        discoveredControlCount: Int,
        reprogControlCount: Int,
        hasInflightWork: Bool
    ) -> ReceiverReconnectAction {
        return receiverReconnectAction(
            hasReprogFeature: hasReprogFeature,
            discoveredControlCount: discoveredControlCount,
            reprogControlCount: reprogControlCount,
            hasInflightWork: hasInflightWork
        )
    }

    internal static func receiverConnectionNotificationActionForTests(
        currentDeviceIndex: UInt8,
        incomingDeviceIndex: UInt8,
        connected: Bool,
        currentTargetIsConnected: Bool,
        reprogInitComplete: Bool,
        hasInflightWork: Bool
    ) -> ReceiverConnectionNotificationAction {
        return receiverConnectionNotificationAction(
            currentDeviceIndex: currentDeviceIndex,
            incomingDeviceIndex: incomingDeviceIndex,
            connected: connected,
            currentTargetConnectionIsKnown: true,
            currentTargetIsConnected: currentTargetIsConnected,
            reprogInitComplete: reprogInitComplete,
            hasInflightWork: hasInflightWork
        )
    }
    #endif

    // MARK: - Setup / Teardown

    func setup() {
        isBLE = transport.lowercased().contains("bluetooth")

        // 确定连接模式
        if isBLE {
            connectionMode = .bleDirect
            deviceIndex = 0xFF
        } else if usagePage == 0xFF00 || usagePage == 0xFF43 || usagePage == 0xFFC0 {
            connectionMode = .receiver
            deviceIndex = 0x01  // 临时值, 枚举后会自动更新到实际在线 slot
        } else {
            connectionMode = .unsupported
        }

        let tag = "[\(deviceInfo.name):\(String(format: "0x%04X", usagePage))/\(String(format: "0x%04X", usage))]"
        LogiDebugPanel.log("\(tag) Setup: transport=\(transport), mode=\(connectionMode), devIdx=\(String(format: "0x%02X", deviceIndex)), isCandidate=\(isHIDPPCandidate)")

        // 只对 HID++ 候选接口进行协议通信
        guard isHIDPPCandidate else {
            LogiDebugPanel.log("\(tag) Skipping: not a HID++ candidate interface")
            // 仍然注册 input report 回调以捕获广播通知 (如 SmartShift)
            setupInputReportCallback()
            return
        }

        // 显式打开设备 (IOHIDManagerOpen 可能不够)
        let openResult = IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            deviceOpened = true
            LogiDebugPanel.log("\(tag) IOHIDDeviceOpen: OK")
        } else {
            LogiDebugPanel.log("\(tag) IOHIDDeviceOpen: failed \(String(format: "0x%08x", openResult)), proceeding anyway")
        }

        setupInputReportCallback()

        // 标记初次 discovery 开始 (覆盖 receiver enumeration + BLE direct discovery + 缓存验证),
        // UI 打开 debug panel 时能看到 Initializing spinner.
        setDiscoveryInFlight(true)

        // Receiver 模式: 先枚举 slot, 找到在线设备后自动 target + feature discovery
        if connectionMode == .receiver {
            LogiDebugPanel.log("\(tag) Receiver mode: enumerating paired devices...")
            enumerateReceiverDevices()
            return
        }

        // BLE / 直连模式: 直接 Feature Discovery (尝试缓存, 失败则完整 discovery)
        if let cached = Self.loadCachedFeatureIndex(for: deviceInfo.productId),
           let reprogIdx = cached[Self.featureReprogV4] {
            LogiDebugPanel.log("\(tag) Using cached feature index: REPROG at 0x\(String(format: "%02X", reprogIdx))")
            self.featureIndex = cached.reduce(into: [UInt16: UInt8]()) { $0[$1.key] = $1.value }
            // 用 ping 验证缓存是否有效 (IRoot.GetProtocolVersion)
            sendRequest(featureIndex: 0x00, functionId: 1)
            pendingCacheValidation = reprogIdx
        } else {
            LogiDebugPanel.log("\(tag) Starting feature discovery for REPROG_CONTROLS_V4 (0x1B04)")
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
        LogiDebugPanel.log("[\(deviceInfo.name)] Teardown")
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        controlInfoQueryTimer?.invalidate()
        controlInfoQueryTimer = nil
        reportingQueryTimer?.invalidate()
        reportingQueryTimer = nil
        pendingDiscovery.removeAll()
        controlInfoRetryCounts.removeAll()
        cancelDivertReassertion()
        cancelBLEStandardUndivertGuard()
        releaseAllActiveButtonState(reason: "teardown")
        if let reprogIdx = featureIndex[Self.featureReprogV4] {
            for cid in divertedCIDs {
                setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
            }
        }
        cancelDivertReassertion()
        pendingSetControlReportingAcks.removeAll()
        lastApplied.removeAll()
        divertedCIDs.removeAll()
        discoveredControls.removeAll()
        // timer 已清零, 此时 isActivityInProgress 只剩 discoveryInFlight 一个分量;
        // 走 setter 让 Manager 重算聚合 busy, 防止 session 销毁后 UI spinner 卡住.
        setDiscoveryInFlight(false)
    }

    // MARK: - Input Report Callback

    static let inputReportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
        guard let context = context else { return }
        let session = Unmanaged<LogiDeviceSession>.fromOpaque(context).takeUnretainedValue()
        let buffer = UnsafeBufferPointer(start: report, count: reportLength)
        session.handleInputReport(buffer)
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
            LogiDebugPanel.log(device: deviceInfo.name, type: .warning, message: "Cannot send: unsupported connection mode")
            return
        }

        let hex = report.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        let resultStr = result == kIOReturnSuccess ? "OK" : String(format: "0x%08x", result)
        let decoded = decodeRequest(featureIndex: featureIndex, functionId: functionId, params: params)
        LogiDebugPanel.log(device: deviceInfo.name, type: .tx, message: "TX: \(hex)... -> \(resultStr)", decoded: decoded)
    }

    // MARK: - Feature Discovery

    private func startFreshDiscovery(tag: String) {
        discoverFeature(featureId: Self.featureReprogV4) { [weak self] index in
            guard let self = self else { return }
            guard let index = index else {
                LogiDebugPanel.log("\(tag) REPROG_CONTROLS_V4 not available")
                // Discovery 走到终点但未命中 REPROG, 仍算握手完成 (Mos 能做的已经做完).
                self.markHandshakeComplete()
                NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
                LogiSessionManager.shared.recomputeAndNotifyActivityState()
                return
            }
            self.featureIndex[Self.featureReprogV4] = index
            LogiDebugPanel.log("\(tag) REPROG_CONTROLS_V4 at index \(String(format: "0x%02X", index))")
            // 缓存 feature index
            Self.saveCachedFeatureIndex(for: self.deviceInfo.productId, featureMap: self.featureIndex)
            self.sendGetControlCount(featureIndex: index)
        }
    }

    /// 置 handshake 终态并通知 sidebar 刷新.
    /// 同一 session 多次调用安全 (仅在首次 false→true 过渡时 post).
    private func markHandshakeComplete() {
        setDiscoveryInFlight(false)
        guard !handshakeComplete else { return }
        handshakeComplete = true
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
    }

    /// discoveryInFlight 切换 + 通知. idempotent: 只在状态变化时 post.
    private func setDiscoveryInFlight(_ flag: Bool) {
        guard discoveryInFlight != flag else { return }
        discoveryInFlight = flag
        NotificationCenter.default.post(name: LogiSessionManager.discoveryStateDidChangeNotification, object: nil)
        LogiSessionManager.shared.recomputeAndNotifyActivityState()
    }

    /// 任一阶段 (discovery / reporting query) 正在进行; UI 据此驱动 activity spinner.
    var isActivityInProgress: Bool {
        return discoveryInFlight || reportingQueryTimer != nil
    }

    /// 供 UI hover popover 读取的 session 级活动快照. 无活动时返回 nil.
    /// 只读投影, 不改变任何内部状态; 读线程与 HID++ 回调一致 (main).
    var activityStatus: SessionActivityStatus? {
        // reporting query 比 discovery 后发生, 信息更细 (可给出进度), 优先展示.
        if reportingQueryTimer != nil {
            let total = discoveredControls.count
            // reportingQueryIndex 是下一个待发的索引; 展示用 index+1 更贴近"正在查第几个"
            let current = min(reportingQueryIndex + 1, max(total, 1))
            return SessionActivityStatus(
                phase: .reportingQuery,
                deviceName: deviceInfo.name,
                progress: total > 0 ? (current, total) : nil
            )
        }
        if discoveryInFlight {
            return SessionActivityStatus(
                phase: .discovery,
                deviceName: deviceInfo.name,
                progress: nil
            )
        }
        return nil
    }

    private func discoverFeature(featureId: UInt16, completion: @escaping (UInt8?) -> Void) {
        let params: [UInt8] = [UInt8(featureId >> 8), UInt8(featureId & 0xFF)]
        sendRequest(featureIndex: 0x00, functionId: 0, params: params)
        pendingDiscovery[featureId] = completion

        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: Self.discoveryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if let pending = self.pendingDiscovery.removeValue(forKey: featureId) {
                LogiDebugPanel.log("[\(self.deviceInfo.name)] Feature discovery timed out for \(String(format: "0x%04X", featureId))")
                pending(nil)
            }
        }
    }

    // MARK: - REPROG_CONTROLS_V4 Flow

    private func sendGetControlCount(featureIndex: UInt8) {
        LogiDebugPanel.log("[\(deviceInfo.name)] Sending GetControlCount")
        sendRequest(featureIndex: featureIndex, functionId: 0)
    }

    private func sendGetControlInfo(featureIndex: UInt8, index: Int) {
        LogiDebugPanel.log("[\(deviceInfo.name)] Sending GetControlInfo(\(index))")
        sendRequest(featureIndex: featureIndex, functionId: 1, params: [UInt8(index)])
        scheduleControlInfoTimeout(index: index)
    }

    private func scheduleControlInfoTimeout(index: Int) {
        controlInfoQueryTimer?.invalidate()
        controlInfoQueryTimer = Timer.scheduledTimer(withTimeInterval: Self.reprogQueryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let retryCount = self.controlInfoRetryCounts[index] ?? 0
            if Self.shouldRetryControlInfoTimeout(
                connectionMode: self.connectionMode,
                retryCount: retryCount
            ), let idx = self.featureIndex[Self.featureReprogV4] {
                self.controlInfoRetryCounts[index] = retryCount + 1
                LogiDebugPanel.log(
                    "[\(self.deviceInfo.name)] GetControlInfo[\(index)] timed out, retrying (\(retryCount + 1)/\(Self.bleControlInfoRetryLimit))"
                )
                self.sendGetControlInfo(featureIndex: idx, index: index)
                return
            }

            self.controlInfoRetryCounts.removeValue(forKey: index)
            LogiDebugPanel.log("[\(self.deviceInfo.name)] GetControlInfo[\(index)] timed out, skipping")
            self.advanceControlInfoQuery()
        }
    }

    /// 推进 controlInfo 查询 (正常响应 / 错误 / 超时 都调此方法)
    private func advanceControlInfoQuery() {
        controlInfoQueryTimer?.invalidate()
        controlInfoQueryTimer = nil
        controlInfoRetryCounts.removeValue(forKey: reprogQueryIndex)
        reprogQueryIndex += 1
        if reprogQueryIndex < reprogControlCount, let idx = featureIndex[Self.featureReprogV4] {
            sendGetControlInfo(featureIndex: idx, index: reprogQueryIndex)
        } else {
            // ControlInfo 全部获取完毕, 开始逐个查询 reporting 状态
            startReportingQuery()
        }
    }

    private func setControlReporting(featureIndex: UInt8, cid: UInt16, divert: Bool) {
        sendControlReporting(
            featureIndex: featureIndex,
            cid: cid,
            divert: divert,
            updateLocalState: true,
            debugSource: "setControlReporting"
        )
    }

    private func sendControlReporting(
        featureIndex: UInt8,
        cid: UInt16,
        divert: Bool,
        updateLocalState: Bool,
        debugSource: String
    ) {
        let params = Self.controlReportingParams(
            connectionMode: connectionMode,
            cid: cid,
            divert: divert
        )
        guard !params.isEmpty else { return }
        recordPendingSetControlReportingAck(cid: cid, params: params)
        sendRequest(featureIndex: featureIndex, functionId: 3,
                         params: params)
        if updateLocalState {
            if divert { divertedCIDs.insert(cid) } else { divertedCIDs.remove(cid) }
        }
        // 方案 B: 不再本地改写 reportingFlags.
        // reportingFlags 永远反映 "GetControlReporting 响应的真值" (设备层状态, Mos 接管前).
        // Mos 自己的 divert 视角由 divertedCIDs 集合唯一表达, 避免污染冲突判定的依据.
        LogiDebugPanel.log("[\(deviceInfo.name)] CID \(String(format: "0x%04X", cid)) divert=\(divert ? "ON" : "OFF")")
        #if DEBUG
        LogiTrace.log(
            "[Session] \(debugSource) cid=\(String(format: "0x%04X", cid)) divert=\(divert) params=\(params.map { String(format: "%02X", $0) }.joined(separator: " ")) localState=\(updateLocalState ? "updated" : "preserved") diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
    }

    private func recordPendingSetControlReportingAck(cid: UInt16, params: [UInt8]) {
        guard params.count >= 5 else { return }
        let targetCID = (UInt16(params[3]) << 8) | UInt16(params[4])
        pendingSetControlReportingAcks[cid] = PendingSetControlReportingAck(
            flagsByte: params[2],
            targetCID: targetCID,
            expiresAt: Date().addingTimeInterval(Self.pendingSetControlReportingAckTTL)
        )
        #if DEBUG
        LogiTrace.log(
            "[Session] pending SetReporting ACK cid=\(String(format: "0x%04X", cid)) flags=\(String(format: "0x%02X", params[2])) target=\(String(format: "0x%04X", targetCID))",
            device: deviceInfo.name
        )
        #endif
    }

    private func consumePendingSetControlReportingAck(_ ack: SetControlReportingAck) -> Bool {
        guard let pending = pendingSetControlReportingAcks[ack.cid] else {
            #if DEBUG
            LogiTrace.log(
                "[Session] SetReporting ACK no pending cid=\(String(format: "0x%04X", ack.cid)) flags=\(String(format: "0x%02X", ack.flagsByte)) target=\(String(format: "0x%04X", ack.targetCID))",
                device: deviceInfo.name
            )
            #endif
            return false
        }
        guard Date() <= pending.expiresAt else {
            pendingSetControlReportingAcks.removeValue(forKey: ack.cid)
            #if DEBUG
            LogiTrace.log(
                "[Session] SetReporting ACK pending expired cid=\(String(format: "0x%04X", ack.cid))",
                device: deviceInfo.name
            )
            #endif
            return false
        }
        guard pending.flagsByte == ack.flagsByte,
              pending.targetCID == ack.targetCID else {
            #if DEBUG
            LogiTrace.log(
                "[Session] SetReporting ACK pending mismatch cid=\(String(format: "0x%04X", ack.cid)) pendingFlags=\(String(format: "0x%02X", pending.flagsByte)) ackFlags=\(String(format: "0x%02X", ack.flagsByte)) pendingTarget=\(String(format: "0x%04X", pending.targetCID)) ackTarget=\(String(format: "0x%04X", ack.targetCID))",
                device: deviceInfo.name
            )
            #endif
            return false
        }
        pendingSetControlReportingAcks.removeValue(forKey: ack.cid)
        #if DEBUG
        LogiTrace.log(
            "[Session] SetReporting ACK consumed cid=\(String(format: "0x%04X", ack.cid)) flags=\(String(format: "0x%02X", ack.flagsByte)) target=\(String(format: "0x%04X", ack.targetCID))",
            device: deviceInfo.name
        )
        #endif
        return true
    }

    private static func controlReportingParams(
        connectionMode: ConnectionMode,
        cid: UInt16,
        divert: Bool
    ) -> [UInt8] {
        let cidH = UInt8(cid >> 8)
        let cidL = UInt8(cid & 0xFF)
        // HID++ Xvalid: bit0=divert value, bit1=divert valid.
        let flagsByte: UInt8 = divert ? 0x03 : 0x02

        switch connectionMode {
        case .bleDirect, .receiver:
            // targetCID=0x0000: 不改变现有 remap 目标; BLE/Bolt 默认保持同一策略.
            return [cidH, cidL, flagsByte, 0x00, 0x00]
        case .unsupported:
            return []
        }
    }

    #if DEBUG
    internal static func controlReportingParamsForTests(
        connectionMode: ConnectionMode,
        cid: UInt16,
        divert: Bool
    ) -> [UInt8] {
        return controlReportingParams(connectionMode: connectionMode, cid: cid, divert: divert)
    }
    #endif

    // MARK: - Debug Operations (interactive divert control)

    func rediscoverFeatures() {
        cancelInflightDiscovery()
        featureIndex.removeAll()
        discoveredControls.removeAll()
        reprogInitComplete = false
        handshakeComplete = false  // 允许 markHandshakeComplete 再次 post sessionChanged 以刷右侧面板
        reprogControlCount = 0
        reprogQueryIndex = 0
        reportingQueryIndex = 0
        controlInfoRetryCounts.removeAll()
        releaseAllActiveButtonState(reason: "rediscover")
        lastApplied.removeAll()
        divertedCIDs.removeAll()
        LogiDebugPanel.log("[\(deviceInfo.name)] Re-discovering features...")
        setDiscoveryInFlight(true)
        // 复用 startFreshDiscovery 的完整握手流程: 成功走 sendGetControlCount,
        // REPROG 不可用分支会 markHandshakeComplete(), 避免卡在 initializing.
        startFreshDiscovery(tag: "[\(deviceInfo.name)]")
    }

    /// 取消所有正在进行的 discovery/query timer 与 pending callback.
    /// 用途: 用户连续切 slot 或手动 rediscover 时, 防止上一轮响应/超时推进
    /// advance...() 流程, 避免错误把新 target 标为 ready.
    /// 只清 dict 不主动触发 callback(nil): 旧响应到达时找不到 callback 自然被忽略,
    /// 避免触发 markHandshakeComplete 造成 ready→init 的 UI 闪烁.
    private func cancelInflightDiscovery() {
        discoveryTimer?.invalidate(); discoveryTimer = nil
        controlInfoQueryTimer?.invalidate(); controlInfoQueryTimer = nil
        reportingQueryTimer?.invalidate(); reportingQueryTimer = nil
        pendingDiscovery.removeAll()
        pendingCacheValidation = nil
        controlInfoRetryCounts.removeAll()
        cancelDivertReassertion()
        cancelBLEStandardUndivertGuard()
        pendingSetControlReportingAcks.removeAll()
    }

    private func cancelDivertReassertion() {
        divertReassertionWorkItem?.cancel()
        divertReassertionWorkItem = nil
    }

    private func cancelBLEStandardUndivertGuard() {
        #if DEBUG
        if bleStandardUndivertGuardWorkItem != nil || !bleStandardUndivertGuardTargets.isEmpty {
            LogiTrace.log("[StandardButtonGuard] cancel generation=\(bleStandardUndivertGuardGeneration) targets=\(LogiTrace.cids(bleStandardUndivertGuardTargets))", device: deviceInfo.name)
        }
        #endif
        bleStandardUndivertGuardGeneration += 1
        bleStandardUndivertGuardWorkItem?.cancel()
        bleStandardUndivertGuardWorkItem = nil
        bleStandardUndivertGuardTargets.removeAll()
        pendingBLEUndivertGuardQueries.removeAll()
    }

    func redivertAllControls() {
        releaseAllActiveButtonState(reason: "redivert")
        cancelBLEStandardUndivertGuard()
        reprogInitComplete = true
        divertedCIDs.removeAll()
        lastApplied.removeAll()
        primeFromRegistry()
        LogiDebugPanel.log("[\(deviceInfo.name)] Re-synced divert with bindings")
    }

    func undivertAllControls() {
        releaseAllActiveButtonState(reason: "undivert all")
        cancelBLEStandardUndivertGuard()
        guard currentReceiverTargetIsConnected else {
            lastApplied.removeAll()
            divertedCIDs.removeAll()
            reprogInitComplete = false
            LogiDebugPanel.log("[\(deviceInfo.name)] Cleared local divert state; receiver target disconnected")
            return
        }
        guard let idx = featureIndex[Self.featureReprogV4] else {
            lastApplied.removeAll()
            reprogInitComplete = false
            LogiDebugPanel.log("[\(deviceInfo.name)] Cleared local divert state; REPROG feature unavailable")
            return
        }
        for cid in divertedCIDs {
            setControlReporting(featureIndex: idx, cid: cid, divert: false)
        }
        lastApplied.removeAll()
        reprogInitComplete = false
        LogiDebugPanel.log("[\(deviceInfo.name)] Undiverted all controls")
    }

    func toggleDivert(cid: UInt16) {
        guard let idx = featureIndex[Self.featureReprogV4] else { return }
        guard currentReceiverTargetIsConnected else { return }
        let currentlyDiverted = divertedCIDs.contains(cid)
        setControlReporting(featureIndex: idx, cid: cid, divert: !currentlyDiverted)
    }

    // MARK: - Receiver Slot Targeting

    /// 切换目标 slot (debug 面板交互/自动选择)
    func setTargetSlot(slot: UInt8) {
        guard connectionMode == .receiver, slot >= 1, slot <= 6 else { return }
        cancelInflightDiscovery()
        deviceIndex = slot
        // 重置 feature 状态, 等待新一轮 discovery
        featureIndex.removeAll()
        discoveredControls.removeAll()
        reprogInitComplete = false
        handshakeComplete = false  // 允许 markHandshakeComplete 再次 post, 使 sidebar/panels 刷新回 loading/ready 切换
        reprogControlCount = 0
        reprogQueryIndex = 0
        reportingQueryIndex = 0
        releaseAllActiveButtonState(reason: "target slot changed")
        lastApplied.removeAll()
        divertedCIDs.removeAll()
        setDiscoveryInFlight(true)
        LogiDebugPanel.log("[\(deviceInfo.name)] Target slot changed to \(slot)")
    }

    // MARK: - Receiver Device Enumeration

    /// 枚举 receiver 上的配对设备 (ping 所有 slot + 查询设备信息)
    func enumerateReceiverDevices() {
        guard connectionMode == .receiver else { return }
        receiverPairedDevices = (1...6).map { ReceiverPairedDevice(slot: UInt8($0)) }
        pendingSlotPings = Set((1 as UInt8)...(6 as UInt8))
        receiverEnumPhase = 1
        LogiDebugPanel.log("[\(deviceInfo.name)] Enumerating receiver slots 1-6...")

        for slot: UInt8 in 1...6 {
            pingReceiverSlot(slot)
        }

        // 超时: 5秒后自动完成 ping 阶段
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.receiverEnumPhase == 1 else { return }
            // 未响应的 slot 标记为未连接
            for slot in self.pendingSlotPings {
                if let idx = self.receiverPairedDevices.firstIndex(where: { $0.slot == slot }) {
                    self.receiverPairedDevices[idx].lastError = "Timeout"
                }
            }
            self.pendingSlotPings.removeAll()
            self.finishPingPhase()
        }
    }

    /// Ping 特定 receiver slot (发送 IRoot.Ping)
    func pingReceiverSlot(_ slot: UInt8) {
        guard connectionMode == .receiver else { return }

        // HID++ 2.0 IRoot.Ping via short report
        // [0x10, devIdx, 0x00(IRoot), 0x1A(func=1,swId=0x0A), 0x00, 0x00, slot(pingData)]
        var report = [UInt8](repeating: 0, count: 7)
        report[0] = Self.hidppShortReportId
        report[1] = slot
        report[2] = 0x00  // IRoot feature index
        report[3] = 0x1A  // function=1(ping), swId=0x0A
        report[4] = 0x00
        report[5] = 0x00
        report[6] = slot  // ping data for matching

        pendingSlotPings.insert(slot)

        let result = IOHIDDeviceSetReport(
            hidDevice, kIOHIDReportTypeOutput,
            CFIndex(report[0]), report, report.count
        )

        let hex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
        let resultStr = result == kIOReturnSuccess ? "OK" : String(format: "0x%08x", result)
        LogiDebugPanel.log(device: deviceInfo.name, type: .tx, message: "TX: \(hex) -> \(resultStr)",
                                  decoded: "IRoot.Ping(slot=\(slot))")
    }

    /// 查询 receiver slot 的设备信息 (register 0xB5)
    func queryReceiverDeviceInfo(slot: UInt8) {
        guard connectionMode == .receiver else { return }
        let entityIdx = slot - 1  // register 0xB5 使用 0-based index

        // 查询设备类型和 wireless PID
        sendReceiverRegisterGet(register: Self.receiverPairingInfo, isLong: true,
                                params: [entityIdx, Self.pairingInfoDeviceInfo])

        // 延迟 100ms 查询设备名称 (避免请求堆积)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.sendReceiverRegisterGet(register: Self.receiverPairingInfo, isLong: true,
                                          params: [entityIdx, Self.pairingInfoDeviceName])
        }
    }

    /// 发送 HID++ 1.0 register GET 请求 (target: receiver 0xFF)
    private func sendReceiverRegisterGet(register: UInt8, isLong: Bool, params: [UInt8] = []) {
        var report: [UInt8]
        let subId: UInt8

        if isLong {
            report = [UInt8](repeating: 0, count: 20)
            report[0] = Self.hidppLongReportId
            subId = Self.hidpp10GetLongRegister
        } else {
            report = [UInt8](repeating: 0, count: 7)
            report[0] = Self.hidppShortReportId
            subId = Self.hidpp10GetRegister
        }

        report[1] = 0xFF  // receiver device index
        report[2] = subId
        report[3] = register
        for (i, p) in params.enumerated() {
            if 4 + i < report.count { report[4 + i] = p }
        }

        let result = IOHIDDeviceSetReport(
            hidDevice, kIOHIDReportTypeOutput,
            CFIndex(report[0]), report, report.count
        )

        let hex = report.prefix(min(report.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        let resultStr = result == kIOReturnSuccess ? "OK" : String(format: "0x%08x", result)
        let regName = register == Self.receiverPairingInfo ? "PairingInfo" : "0x\(String(format: "%02X", register))"
        let paramsHex = params.map { String(format: "%02X", $0) }.joined(separator: " ")
        LogiDebugPanel.log(device: deviceInfo.name, type: .tx, message: "TX: \(hex) -> \(resultStr)",
                                  decoded: "\(isLong ? "GET_LONG" : "GET")_REGISTER(\(regName), [\(paramsHex)])")
    }

    // MARK: - Receiver Response Handlers

    /// 处理 HID++ 1.0 错误响应 (sub-ID 0x8F)
    private func handleHIDPP10Error(_ report: UnsafeBufferPointer<UInt8>) {
        let devIdx = report[1]
        let errorCode = report.count > 5 ? report[5] : 0

        let hidpp10ErrorNames: [UInt8: String] = [
            0x00: "Success", 0x01: "InvalidSubID", 0x02: "InvalidAddress",
            0x03: "InvalidValue", 0x04: "ConnectFailed", 0x05: "TooManyDevices",
            0x06: "AlreadyExists", 0x07: "Busy", 0x08: "UnknownDevice",
            0x09: "ResourceError", 0x0A: "RequestUnavailable", 0x0B: "InvalidParamValue",
        ]
        let errorName = hidpp10ErrorNames[errorCode] ?? "0x\(String(format: "%02X", errorCode))"

        // 更新 receiver slot 状态 (如果是 ping 错误)
        if devIdx >= 1 && devIdx <= 6 && pendingSlotPings.contains(devIdx) {
            pendingSlotPings.remove(devIdx)
            if let idx = receiverPairedDevices.firstIndex(where: { $0.slot == devIdx }) {
                receiverPairedDevices[idx].isConnected = false
                receiverPairedDevices[idx].lastError = errorName
            }
            checkPingPhaseComplete()
        }

        // 只处理来自当前目标设备的 feature discovery 错误
        // (receiver 自身的 register 错误 devIdx=0xFF 不应影响设备的 feature discovery)
        if devIdx == deviceIndex {
            for (featureId, callback) in pendingDiscovery {
                callback(nil)
                pendingDiscovery.removeValue(forKey: featureId)
            }
        }
    }

    /// 处理 ping 响应 (device slot 回复 IRoot.Ping)
    private func handleSlotPingResponse(devIdx: UInt8, report: UnsafeBufferPointer<UInt8>) {
        pendingSlotPings.remove(devIdx)
        let protMajor = report[4]
        let protMinor = report[5]

        if let idx = receiverPairedDevices.firstIndex(where: { $0.slot == devIdx }) {
            receiverPairedDevices[idx].isConnected = true
            receiverPairedDevices[idx].protocolMajor = protMajor
            receiverPairedDevices[idx].protocolMinor = protMinor
            receiverPairedDevices[idx].lastError = nil
        }

        LogiDebugPanel.log(device: deviceInfo.name, type: .info,
            message: "Slot \(devIdx): device connected (HID++ \(protMajor).\(protMinor))")
        checkPingPhaseComplete()
    }

    /// 检查 ping 阶段是否完成
    private func checkPingPhaseComplete() {
        guard pendingSlotPings.isEmpty && receiverEnumPhase == 1 else { return }
        finishPingPhase()
    }

    /// 完成 ping 阶段, 进入 info 查询阶段
    private func finishPingPhase() {
        receiverEnumPhase = 2
        let connectedSlots = receiverPairedDevices.filter { $0.isConnected }
        LogiDebugPanel.log("[\(deviceInfo.name)] Ping complete: \(connectedSlots.count)/6 slots connected")

        // 查询已连接设备的详细信息 (register 0xB5, 可能在 Bolt receiver 上失败)
        for dev in connectedSlots {
            queryReceiverDeviceInfo(slot: dev.slot)
        }

        // 自动 target 第一个在线设备并启动 feature discovery
        if let firstConnected = connectedSlots.first {
            deviceIndex = firstConnected.slot
            featureIndex.removeAll()
            discoveredControls.removeAll()
            reprogInitComplete = false
            LogiDebugPanel.log("[\(deviceInfo.name)] Auto-targeted slot \(firstConnected.slot)")

            let tag = "[\(deviceInfo.name):slot\(firstConnected.slot)]"
            LogiDebugPanel.log("\(tag) Starting feature discovery for REPROG_CONTROLS_V4 (0x1B04)")
            startFreshDiscovery(tag: tag)
        } else {
            receiverEnumPhase = 0
            LogiDebugPanel.log("[\(deviceInfo.name)] No devices found on receiver")
            // 无设备 -> 不会进 peripheral discovery, 此处必须清 inflight 防止 spinner 一直转.
            setDiscoveryInFlight(false)
        }

        // Receiver dongle 本身的握手 = slot ping 完成. 后续 peripheral discovery 状态与此独立.
        handshakeComplete = true
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
    }

    /// 处理 receiver register 响应
    private func handleReceiverRegisterResponse(_ report: UnsafeBufferPointer<UInt8>) {
        let register = report[3]

        if register == Self.receiverPairingInfo {
            let entityIdx = report[4]  // 0-based
            let infoType = report[5]
            let slot = entityIdx + 1

            guard let idx = receiverPairedDevices.firstIndex(where: { $0.slot == slot }) else { return }

            if infoType == Self.pairingInfoDeviceInfo && report.count > 10 {
                // [entityIdx, 0x20, destId, reportInterval, wirelessPID_hi, wirelessPID_lo, deviceType, ...]
                receiverPairedDevices[idx].wirelessPID = (UInt16(report[8]) << 8) | UInt16(report[9])
                receiverPairedDevices[idx].deviceType = report[10]
                LogiDebugPanel.log(device: deviceInfo.name, type: .info,
                    message: "Slot \(slot) info: type=\(receiverPairedDevices[idx].deviceTypeName) wirelessPID=\(String(format: "0x%04X", receiverPairedDevices[idx].wirelessPID))")
            } else if infoType == Self.pairingInfoDeviceName && report.count > 7 {
                // [entityIdx, 0x40, nameLen, char0, char1, ...]
                let nameLen = min(Int(report[6]), report.count - 7)
                if nameLen > 0 {
                    let nameBytes = Array(report[7..<(7 + nameLen)])
                    receiverPairedDevices[idx].name = String(bytes: nameBytes, encoding: .utf8) ?? ""
                    LogiDebugPanel.log(device: deviceInfo.name, type: .info,
                        message: "Slot \(slot) name: \"\(receiverPairedDevices[idx].name)\"")
                }
            }

            NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
        }
    }

    /// 处理设备连接/断开通知 (sub-ID 0x41)
    private func handleDeviceConnectionNotification(_ report: UnsafeBufferPointer<UInt8>) {
        let devIdx = report[1]
        let protocolType = report.count > 3 ? report[3] : 0
        let devInfo = report.count > 4 ? report[4] : 0
        let connected = (devInfo & 0x40) == 0  // bit 6 = 0: link established

        LogiDebugPanel.log(device: deviceInfo.name, type: .info,
            message: "Device \(connected ? "connected" : "disconnected") on slot \(devIdx) (protocol=\(String(format: "0x%02X", protocolType)))")

        if devIdx >= 1 && devIdx <= 6 {
            if let idx = receiverPairedDevices.firstIndex(where: { $0.slot == devIdx }) {
                receiverPairedDevices[idx].isConnected = connected
            } else {
                // 自动追加 (如果枚举尚未运行)
                var dev = ReceiverPairedDevice(slot: devIdx)
                dev.isConnected = connected
                receiverPairedDevices.append(dev)
                receiverPairedDevices.sort { $0.slot < $1.slot }
            }

            let hasInflightWork = discoveryTimer != nil || controlInfoQueryTimer != nil || reportingQueryTimer != nil
            let action = Self.receiverConnectionNotificationAction(
                currentDeviceIndex: deviceIndex,
                incomingDeviceIndex: devIdx,
                connected: connected,
                currentTargetConnectionIsKnown: currentReceiverTargetConnectionIsKnown,
                currentTargetIsConnected: currentReceiverTargetIsConnected,
                reprogInitComplete: reprogInitComplete,
                hasInflightWork: hasInflightWork
            )
            LogiDebugPanel.log(
                "[\(deviceInfo.name)] DeviceConnection action=\(action.debugLabel) current=\(deviceIndex) incoming=\(devIdx) currentKnown=\(currentReceiverTargetConnectionIsKnown) currentConnected=\(currentReceiverTargetIsConnected) reprogInit=\(reprogInitComplete) inflight=\(hasInflightWork)"
            )

            switch action {
            case .ignore:
                break
            case .currentTargetConnected:
                handleCurrentReceiverTargetReconnected()
            case .currentTargetDisconnected:
                handleCurrentReceiverTargetDisconnected()
            case .retarget(let slot):
                setTargetSlot(slot: slot)
                rediscoverFeatures()
            }
            NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
        }
    }

    private func handleCurrentReceiverTargetDisconnected() {
        cancelInflightDiscovery()
        releaseAllActiveButtonState(reason: "receiver target disconnected")
        lastApplied.removeAll()
        divertedCIDs.removeAll()
        reprogInitComplete = false
        handshakeComplete = false
        reportingQueryIndex = 0
        setDiscoveryInFlight(false)
        LogiDebugPanel.log("[\(deviceInfo.name)] Current receiver target disconnected; local divert state cleared")
    }

    private func handleCurrentReceiverTargetReconnected() {
        guard connectionMode == .receiver else { return }
        let hasInflightWork = discoveryTimer != nil || controlInfoQueryTimer != nil || reportingQueryTimer != nil
        let action = Self.receiverReconnectAction(
            hasReprogFeature: featureIndex[Self.featureReprogV4] != nil,
            discoveredControlCount: discoveredControls.count,
            reprogControlCount: reprogControlCount,
            hasInflightWork: hasInflightWork
        )

        switch action {
        case .ignore:
            return
        case .refreshReporting:
            LogiDebugPanel.log("[\(deviceInfo.name)] Current receiver target reconnected; refreshing reporting state")
            setDiscoveryInFlight(true)
            startReportingQuery()
        case .rediscoverFeatures:
            LogiDebugPanel.log("[\(deviceInfo.name)] Current receiver target reconnected; rediscovering features")
            rediscoverFeatures()
        }
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
            case 2:
                if params.count >= 2 {
                    let cid = (UInt16(params[0]) << 8) | UInt16(params[1])
                    return "REPROG.GetControlReporting(CID=\(String(format: "0x%04X", cid)) \(LogiCIDDirectory.name(forCID: cid)))"
                }
                return "REPROG.GetControlReporting"
            case 3:
                if params.count >= 3 {
                    let cid = (UInt16(params[0]) << 8) | UInt16(params[1])
                    let cidName = LogiCIDDirectory.name(forCID: cid)
                    let divert = params[2] & 0x01 != 0
                    return "REPROG.SetControlReporting(CID=\(String(format: "0x%04X", cid)) \(cidName), divert=\(divert ? "ON" : "OFF"))"
                }
                return "REPROG.SetControlReporting"
            default: return "REPROG.func\(functionId)"
            }
        }
        return "Feature[0x\(String(format: "%02X", featureIndex))].func\(functionId)"
    }

    private func decodeReport(_ report: UnsafeBufferPointer<UInt8>) -> String {
        guard report.count >= 7 else { return "short report" }
        let devIdx = report[1]
        let featIdx = report[2]
        let funcId = report[3] >> 4
        let softwareId = report[3] & 0x0F

        // HID++ 1.0 error (sub-ID 0x8F)
        if connectionMode == .receiver && featIdx == Self.hidpp10ErrorMsg {
            let errorSubId = report[3]
            let errorCode = report.count > 5 ? report[5] : 0
            let hidpp10ErrNames: [UInt8: String] = [
                0x01: "InvalidSubID", 0x02: "InvalidAddress", 0x03: "InvalidValue",
                0x04: "ConnectFailed", 0x05: "TooManyDevices", 0x06: "AlreadyExists",
                0x07: "Busy", 0x08: "UnknownDevice", 0x09: "ResourceError",
            ]
            let errName = hidpp10ErrNames[errorCode] ?? "0x\(String(format: "%02X", errorCode))"
            return "HID++ 1.0 ERROR: dev=\(String(format: "0x%02X", devIdx)) subId=\(String(format: "0x%02X", errorSubId)) err=\(errName)"
        }

        // HID++ 1.0 register response from receiver
        if connectionMode == .receiver && devIdx == 0xFF &&
           (featIdx == Self.hidpp10GetRegister || featIdx == Self.hidpp10GetLongRegister) {
            let regAddr = report[3]
            let regName: String
            switch regAddr {
            case Self.receiverPairingInfo: regName = "PairingInfo"
            case 0x00: regName = "Notifications"
            case 0x02: regName = "ConnectionState"
            default: regName = "0x\(String(format: "%02X", regAddr))"
            }
            return "Register \(featIdx == Self.hidpp10GetLongRegister ? "GET_LONG" : "GET"): \(regName)"
        }

        // Device connection notification (sub-ID 0x41)
        if connectionMode == .receiver && featIdx == Self.hidpp10DeviceConnection {
            let devInfo = report.count > 4 ? report[4] : 0
            let connected = (devInfo & 0x40) == 0
            return "DeviceConnection: slot=\(devIdx) \(connected ? "CONNECTED" : "DISCONNECTED")"
        }

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
            if funcId == 0 && softwareId == 0x00 {
                var cids: [String] = []
                var offset = 4
                while offset + 1 < report.count {
                    let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
                    if cid == 0 { break }
                    let name = LogiCIDDirectory.name(forCID: cid)
                    cids.append("\(String(format: "0x%04X", cid))(\(name))")
                    offset += 2
                }
                return cids.isEmpty ? "BUTTON EVENT: all released" : "BUTTON EVENT: \(cids.joined(separator: " + "))"
            }
            if funcId == 0 && softwareId == 0x01 {
                return reprogInitComplete
                    ? "REPROG.ControlCount response = \(report[4])"
                    : "REPROG.ControlCount = \(report[4])"
            }
            if !reprogInitComplete && funcId == 0 {
                return "REPROG.func0 swid=\(softwareId) ignored during init"
            }
            if funcId == 1 {
                let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
                let name = LogiCIDDirectory.name(forCID: cid)
                return "REPROG.ControlInfo: CID=\(String(format: "0x%04X", cid)) (\(name))"
            }
            if funcId == 2 && report.count >= 9 {
                let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
                let rFlags = report[6]
                let tCID = (UInt16(report[7]) << 8) | UInt16(report[8])
                let cidName = LogiCIDDirectory.name(forCID: cid)
                var parts: [String] = []
                if rFlags & 0x01 != 0 { parts.append("tmpDvrt") }
                if rFlags & 0x02 != 0 { parts.append("pstDvrt") }
                if rFlags & 0x04 != 0 { parts.append("tmpRemap") }
                if rFlags & 0x08 != 0 { parts.append("pstRemap") }
                let fStr = parts.isEmpty ? "none" : parts.joined(separator: ",")
                let tStr = tCID != cid && tCID != 0 ? " -> \(LogiCIDDirectory.name(forCID: tCID))" : ""
                return "REPROG.GetReporting(\(cidName)): \(fStr)\(tStr)"
            }
            if funcId == 3 {
                if let ack = Self.parseSetControlReportingAck(report) {
                    let cidName = LogiCIDDirectory.name(forCID: ack.cid)
                    let divert = ack.temporaryDivertEnabled ? "ON" : "OFF"
                    return "REPROG.SetControlReporting ACK: CID=\(String(format: "0x%04X", ack.cid)) (\(cidName)) divert=\(divert)"
                }
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
    private var pendingDPICycle: (featureIndex: UInt8, direction: Direction)? = nil
    private var pendingDPIListQuery: (featureIndex: UInt8, direction: Direction)? = nil
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
                    LogiDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] SmartShift feature not supported")
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
    func executeDPICycle(direction: Direction) {
        // AdjustableDPI feature ID = 0x2201
        let dpiFeatureId: UInt16 = 0x2201
        if let idx = featureIndex[dpiFeatureId] {
            cycleDPI(featureIndex: idx, direction: direction)
        } else {
            discoverFeature(featureId: dpiFeatureId) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogiDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] AdjustableDPI feature not supported")
                    return
                }
                self.featureIndex[dpiFeatureId] = idx
                self.cycleDPI(featureIndex: idx, direction: direction)
            }
        }
    }

    private func cycleDPI(featureIndex: UInt8, direction: Direction) {
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
                    LogiDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] ChangeHost feature not supported")
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
                    LogiDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] ChangeHost feature not supported")
                    return
                }
                self.featureIndex[changeHostFeatureId] = idx
                self.sendRequest(featureIndex: idx, functionId: 0)
                self.pendingHostCycle = idx
            }
        }
    }

    private func switchToHost(featureIndex: UInt8, hostIndex: UInt8) {
        LogiDebugPanel.log("[\(deviceInfo.name)] Switching to host \(hostIndex + 1)")
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
                    self?.showFeatureNotAvailable("Hi-Res Scroll")
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
            sendRequest(featureIndex: idx, functionId: 0x10, params: [])
        } else {
            discoverFeature(featureId: Self.featureHiResWheel) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    self?.showFeatureNotAvailable("Scroll Invert")
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
            sendRequest(featureIndex: idx, functionId: 0x10, params: [])
        } else {
            discoverFeature(featureId: Self.featureThumbWheel) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    self?.showFeatureNotAvailable("Thumb Wheel")
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
            sendRequest(featureIndex: idx, functionId: 0x00, params: [])
        } else {
            discoverFeature(featureId: Self.featurePointerSpeed) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    self?.showFeatureNotAvailable("Pointer Speed")
                    return
                }
                self.featureIndex[Self.featurePointerSpeed] = idx
                self.pendingPointerSpeedCycle = true
                self.sendRequest(featureIndex: idx, functionId: 0x00, params: [])
            }
        }
    }

    /// 显示设备不支持某功能的 Toast 提示
    private func showFeatureNotAvailable(_ featureName: String) {
        let message = String(format: NSLocalizedString("featureNotAvailable", comment: ""),
                            deviceInfo.name, featureName)
        LogiDebugPanel.log("[\(deviceInfo.name)] \(featureName): feature not available")
        LogiCenter.shared.externalBridge.showLogiToast(message, severity: .warning)
    }

    // MARK: - Report Parsing

    private static func isGetControlReportingQueryResponse(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 9 else { return false }
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return functionId == 2 && softwareId == 0x01
    }

    private static func parseReportingResponse(_ report: UnsafeBufferPointer<UInt8>) -> ReportingResponse? {
        guard isGetControlReportingQueryResponse(report) else { return nil }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let targetCID = (UInt16(report[7]) << 8) | UInt16(report[8])
        return ReportingResponse(cid: cid, reportingFlags: report[6], targetCID: targetCID)
    }

    private static func isReportingStateNotification(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 9 else { return false }
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return functionId == 2 && softwareId == 0x00
    }

    private static func parseReportingStateNotification(_ report: UnsafeBufferPointer<UInt8>) -> ReportingResponse? {
        guard isReportingStateNotification(report) else { return nil }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let targetCID = (UInt16(report[7]) << 8) | UInt16(report[8])
        return ReportingResponse(cid: cid, reportingFlags: report[6], targetCID: targetCID)
    }

    private static func isSetControlReportingAck(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 9 else { return false }
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return functionId == 3 && softwareId == 0x01
    }

    private static func parseSetControlReportingAck(_ report: UnsafeBufferPointer<UInt8>) -> SetControlReportingAck? {
        guard isSetControlReportingAck(report) else { return nil }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let targetCID = (UInt16(report[7]) << 8) | UInt16(report[8])
        return SetControlReportingAck(cid: cid, flagsByte: report[6], targetCID: targetCID)
    }

    private static func isDivertedButtonEvent(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 4 else { return false }
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return functionId == 0 && softwareId == 0x00
    }

    private static func reprogInitFunction0Route(_ report: UnsafeBufferPointer<UInt8>) -> ReprogInitFunction0Route {
        guard report.count >= 4 else { return .ignored }
        let functionId = report[3] >> 4
        guard functionId == 0 else { return .ignored }

        switch report[3] & 0x0F {
        case 0x00:
            return .divertedButtonEvent
        case 0x01:
            return .getControlCountResponse
        default:
            return .ignored
        }
    }

    private static func shouldRetryControlInfoTimeout(
        connectionMode: ConnectionMode,
        retryCount: Int
    ) -> Bool {
        return connectionMode == .bleDirect && retryCount < bleControlInfoRetryLimit
    }

    private static func isIRootPingResponse(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 4 else { return false }
        let featureIdx = report[2]
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return featureIdx == 0x00 && functionId == 1 && softwareId == 0x01
    }

    private static func reassertionCIDForSetControlReportingAck(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        ack: SetControlReportingAck,
        isOwnAck: Bool
    ) -> UInt16? {
        guard !isOwnAck,
              lastApplied.contains(ack.cid) || divertedCIDs.contains(ack.cid),
              ack.updatesTemporaryDivert,
              !ack.temporaryDivertEnabled else {
            return nil
        }
        return ack.cid
    }

    private static func reassertionCIDForReportingState(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        state: ReportingResponse
    ) -> UInt16? {
        guard lastApplied.contains(state.cid) || divertedCIDs.contains(state.cid),
              (state.reportingFlags & 0x01) == 0 else {
            return nil
        }
        return state.cid
    }

    #if DEBUG
    internal static func isGetControlReportingQueryResponseForTests(_ bytes: [UInt8]) -> Bool {
        return bytes.withUnsafeBufferPointer { report in
            isGetControlReportingQueryResponse(report)
        }
    }

    internal static func isDivertedButtonEventForTests(_ bytes: [UInt8]) -> Bool {
        return bytes.withUnsafeBufferPointer { report in
            isDivertedButtonEvent(report)
        }
    }

    internal static func reprogInitFunction0RouteForTests(_ bytes: [UInt8]) -> ReprogInitFunction0Route {
        return bytes.withUnsafeBufferPointer { report in
            reprogInitFunction0Route(report)
        }
    }

    internal static func shouldRetryControlInfoTimeoutForTests(
        connectionMode: ConnectionMode,
        retryCount: Int
    ) -> Bool {
        return shouldRetryControlInfoTimeout(
            connectionMode: connectionMode,
            retryCount: retryCount
        )
    }

    internal static func isIRootPingResponseForTests(_ bytes: [UInt8]) -> Bool {
        return bytes.withUnsafeBufferPointer { report in
            isIRootPingResponse(report)
        }
    }

    internal static func reportingResponseForTests(_ bytes: [UInt8], matchesExpectedCID expectedCID: UInt16) -> Bool {
        return bytes.withUnsafeBufferPointer { report in
            parseReportingResponse(report)?.cid == expectedCID
        }
    }

    internal static func setControlReportingAckForTests(
        _ bytes: [UInt8]
    ) -> (cid: UInt16, flagsByte: UInt8, targetCID: UInt16)? {
        return bytes.withUnsafeBufferPointer { report in
            guard let ack = parseSetControlReportingAck(report) else { return nil }
            return (ack.cid, ack.flagsByte, ack.targetCID)
        }
    }

    internal static func reportingStateNotificationForTests(
        _ bytes: [UInt8]
    ) -> (cid: UInt16, reportingFlags: UInt8, targetCID: UInt16)? {
        return bytes.withUnsafeBufferPointer { report in
            guard let state = parseReportingStateNotification(report) else { return nil }
            return (state.cid, state.reportingFlags, state.targetCID)
        }
    }

    internal static func reassertionCIDForSetControlReportingAckForTests(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        ackBytes: [UInt8],
        isOwnAck: Bool
    ) -> UInt16? {
        return ackBytes.withUnsafeBufferPointer { report in
            guard let ack = parseSetControlReportingAck(report) else { return nil }
            return reassertionCIDForSetControlReportingAck(
                lastApplied: lastApplied,
                divertedCIDs: divertedCIDs,
                ack: ack,
                isOwnAck: isOwnAck
            )
        }
    }

    internal static func reassertionCIDForReportingStateForTests(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        bytes: [UInt8]
    ) -> UInt16? {
        return bytes.withUnsafeBufferPointer { report in
            guard let state = parseReportingStateNotification(report) else { return nil }
            return reassertionCIDForReportingState(
                lastApplied: lastApplied,
                divertedCIDs: divertedCIDs,
                state: state
            )
        }
    }

    #endif

    private func handleBLEUndivertGuardReportingResponseIfNeeded(
        _ report: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        guard let response = Self.parseReportingResponse(report),
              let pending = pendingBLEUndivertGuardQueries.removeValue(forKey: response.cid) else {
            return false
        }

        let elapsed = Date().timeIntervalSince(pending.sentAt)
        updateDiscoveredControlReportingState(response, markQueried: true)
        #if DEBUG
        LogiTrace.log(
            "[StandardButtonGuard] RX GetControlReporting cid=\(String(format: "0x%04X", response.cid)) flags=\(String(format: "0x%02X", response.reportingFlags)) target=\(String(format: "0x%04X", response.targetCID)) after=\(String(format: "%.3fs", elapsed)) active=\(LogiTrace.cids(bleStandardUndivertGuardTargets))",
            device: deviceInfo.name
        )
        #endif

        _ = handleStandardButtonGuardState(response, reason: "standard-button guard GetControlReporting")
        return true
    }

    private func handleStandardButtonGuardState(_ state: ReportingResponse, reason: String) -> Bool {
        let targets = bleStandardButtonUndivertPlanner.undivertTargets(
            activeNativeFirstCIDs: bleStandardUndivertGuardTargets,
            reportingFlagsByCID: [state.cid: state.reportingFlags]
        )
        guard targets.contains(state.cid) else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] state did not require OFF cid=\(String(format: "0x%04X", state.cid)) flags=\(String(format: "0x%02X", state.reportingFlags))", device: deviceInfo.name)
            #endif
            return false
        }

        enforceStandardButtonGuard(cid: state.cid, reason: reason)
        return true
    }

    private func enforceStandardButtonGuard(cid: UInt16, reason: String) {
        guard connectionMode == .bleDirect,
              currentReceiverTargetIsConnected,
              bleStandardUndivertGuardTargets.contains(cid),
              let reprogIdx = featureIndex[Self.featureReprogV4] else {
            return
        }

        #if DEBUG
        LogiTrace.log("[StandardButtonGuard] \(reason) -> SetControlReporting OFF cid=\(String(format: "0x%04X", cid))", device: deviceInfo.name)
        LogiDebugPanel.log("[\(deviceInfo.name)] Standard-button guard cleared divert for \(String(format: "0x%04X", cid))")
        #endif
        setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
    }

    private func updateDiscoveredControlReportingState(
        _ response: ReportingResponse,
        markQueried: Bool
    ) {
        guard let idx = discoveredControls.firstIndex(where: { $0.cid == response.cid }) else {
            return
        }
        discoveredControls[idx].reportingFlags = response.reportingFlags
        discoveredControls[idx].targetCID = response.targetCID
        if markQueried {
            discoveredControls[idx].reportingQueried = true
        }
    }

    func handleInputReport(_ report: UnsafeBufferPointer<UInt8>) {
        guard report.count >= 7 else { return }
        guard report[0] == Self.hidppShortReportId || report[0] == Self.hidppLongReportId else { return }

        let hex = report.prefix(min(report.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        let featureIdx = report[2]
        let functionId = report[3] >> 4
        let rxDecoded = decodeReport(report)
        let isError = featureIdx == Self.hidppErrorFeatureIdx ||
            (connectionMode == .receiver && featureIdx == Self.hidpp10ErrorMsg)
        let rxType: LogEntryType = isError ? .error : .rx
        LogiDebugPanel.log(device: deviceInfo.name, type: rxType, message: "RX: \(hex)", decoded: rxDecoded)

        // Receiver mode: route HID++ 1.0 responses first
        if connectionMode == .receiver {
            let devIdx = report[1]

            // HID++ 1.0 error (sub-ID 0x8F)
            if featureIdx == Self.hidpp10ErrorMsg {
                handleHIDPP10Error(report)
                return
            }

            // HID++ 1.0 register response from receiver (device index 0xFF)
            if devIdx == 0xFF && (featureIdx == Self.hidpp10GetRegister || featureIdx == Self.hidpp10GetLongRegister) {
                handleReceiverRegisterResponse(report)
                return
            }

            // Device connection notification (sub-ID 0x41)
            if featureIdx == Self.hidpp10DeviceConnection {
                handleDeviceConnectionNotification(report)
                return
            }

            // Ping response from device behind receiver (IRoot function 1)
            if devIdx >= 1 && devIdx <= 6 && featureIdx == 0x00 && functionId == 1 && pendingSlotPings.contains(devIdx) {
                handleSlotPingResponse(devIdx: devIdx, report: report)
                return
            }

            // Stale-peripheral filter: 用户 retarget 后, 旧 slot 仍可能有 in-flight 响应抵达.
            // 按 deviceIndex 过滤掉"非当前 target"的 peripheral 响应, 防止污染新一轮
            // REPROG discovery state (append 错误 control / advance 错误 index).
            // 0xFF (receiver register) 和 pending ping 已在上面各自处理, 不会进入这里.
            if devIdx >= 1 && devIdx <= 6 && devIdx != deviceIndex {
                LogiDebugPanel.log("[\(deviceInfo.name)] Stale report from slot \(devIdx) (current target=\(deviceIndex)) dropped")
                return
            }
        }

        // HID++ 2.0 Error report
        if featureIdx == Self.hidppErrorFeatureIdx {
            let originalFeatureIdx = report.count > 3 ? report[3] : 0
            let originalFuncId: UInt8 = report.count > 4 ? (report[4] >> 4) : 0
            let errorCode = report.count > 6 ? report[6] : 0
            LogiDebugPanel.log("[\(deviceInfo.name)] HID++ Error: feat=\(String(format: "0x%02X", originalFeatureIdx)) func=\(originalFuncId) err=\(String(format: "0x%02X", errorCode))")

            // Feature discovery pending callbacks
            for (featureId, callback) in pendingDiscovery {
                callback(nil)
                pendingDiscovery.removeValue(forKey: featureId)
            }

            // REPROG_V4 query 错误: 跳过该 CID 继续下一个, 防止 Bolt receiver 上 query 链路卡死
            if let reprogIdx = featureIndex[Self.featureReprogV4],
               originalFeatureIdx == reprogIdx {
                switch originalFuncId {
                case 1 where !reprogInitComplete:  // GetControlInfo
                    LogiDebugPanel.log("[\(deviceInfo.name)] GetControlInfo[\(reprogQueryIndex)] returned error, skipping")
                    advanceControlInfoQuery()
                case 2 where reportingQueryTimer != nil:  // GetControlReporting
                    LogiDebugPanel.log("[\(deviceInfo.name)] GetControlReporting[\(reportingQueryIndex)] returned error, skipping")
                    advanceReportingQuery()
                default:
                    break
                }
            }
            return
        }

        // IRoot response
        if featureIdx == 0x00 {
            // 缓存验证: ping 响应 (function 1) 确认设备在线, 直接用缓存的 feature index
            if let reprogIdx = pendingCacheValidation, functionId == 1 {
                pendingCacheValidation = nil
                LogiDebugPanel.log("[\(deviceInfo.name)] Cache validated (protocol \(report[4]).\(report[5])), using cached index 0x\(String(format: "%02X", reprogIdx))")
                sendGetControlCount(featureIndex: reprogIdx)
                return
            }
            if !pendingDiscovery.isEmpty {
                handleDiscoveryResponse(report)
            }
            return
        }

        // REPROG_CONTROLS_V4
        if let reprogIdx = featureIndex[Self.featureReprogV4], featureIdx == reprogIdx {
            if Self.isGetControlReportingQueryResponse(report),
               handleBLEUndivertGuardReportingResponseIfNeeded(report) {
                return
            }

            if reportingQueryTimer != nil,
               Self.isGetControlReportingQueryResponse(report) {
                handleGetControlReportingResponse(report)
                return
            }

            if Self.isSetControlReportingAck(report) {
                handleSetControlReportingAck(report)
                return
            }

            if reprogInitComplete {
                // init 完成后: function 0 是按键事件; function 2/3 可能是状态通知或 ACK.
                if Self.isDivertedButtonEvent(report) {
                    handleDivertedButtonEvent(report)
                } else if Self.isReportingStateNotification(report) {
                    handleReportingStateNotification(report)
                }
                // function 1/其他 function 2 等忽略
            } else {
                // init 阶段: 按 function ID 路由
                switch functionId {
                case 0:
                    switch Self.reprogInitFunction0Route(report) {
                    case .divertedButtonEvent:
                        #if DEBUG
                        LogiTrace.log("[Session] init-phase REPROG func0 routed as button event", device: deviceInfo.name)
                        #endif
                        handleDivertedButtonEvent(report)
                    case .getControlCountResponse:
                        handleGetControlCountResponse(report)
                    case .ignored:
                        #if DEBUG
                        let softwareId = report[3] & 0x0F
                        LogiTrace.log(
                            "[Session] init-phase REPROG func0 ignored swid=\(String(format: "0x%02X", softwareId))",
                            device: deviceInfo.name
                        )
                        #endif
                    }
                case 1: handleGetControlInfoResponse(report)
                // Redundant fallback: normal reporting queries have a timer and route above.
                case 2 where Self.isGetControlReportingQueryResponse(report):
                    handleGetControlReportingResponse(report)
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
            LogiDebugPanel.log("[\(deviceInfo.name)] SmartShift: \(currentMode == 2 ? "ratchet" : "freewheel") -> \(newMode == 2 ? "ratchet" : "freewheel")")
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
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI range: \(dpiMin)-\(dpiMax) step \(step) (\(dpiSteps.count) levels)")
            } else {
                // 离散列表模式
                dpiSteps = values
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI list: \(dpiSteps)")
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
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI: \(curDPI) -> \(newDPI)")
                // setSensorDpi: function 3, params: sensorIdx(1) + dpi(2)
                sendRequest(featureIndex: dpiInfo.featureIndex, functionId: 3, params: [0x00, UInt8(newDPI >> 8), UInt8(newDPI & 0xFF)])
            } else {
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI: \(curDPI) (already at limit)")
            }
            return
        }

        // ChangeHost response (getHostInfo, function 0) - 用于 cycle
        if let hostIdx = pendingHostCycle, featureIdx == hostIdx && functionId == 0 {
            pendingHostCycle = nil
            let hostCount = report[4]
            let currentHost = report[5]
            let nextHost = (currentHost + 1) % hostCount
            LogiDebugPanel.log("[\(deviceInfo.name)] Host: \(currentHost + 1)/\(hostCount) -> \(nextHost + 1)")
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
                LogiDebugPanel.log("[\(deviceInfo.name)] HiResScroll: \((newMode & 0x02) != 0 ? "ON" : "OFF")")
                return
            }
            if pendingScrollInvertToggle && functionId == 1 {  // response to function 0x10 (0x10 >> 4 = 1)
                let currentMode = report[4]
                let newMode = currentMode ^ 0x04  // Toggle bit 2 (invert)
                sendRequest(featureIndex: hiresIdx, functionId: 0x20, params: [newMode])
                pendingScrollInvertToggle = false
                LogiDebugPanel.log("[\(deviceInfo.name)] ScrollInvert: \((newMode & 0x04) != 0 ? "ON" : "OFF")")
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
                LogiDebugPanel.log("[\(deviceInfo.name)] ThumbWheel: \((newByte1 & 0x01) != 0 ? "DIVERT" : "NORMAL")")
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
                LogiDebugPanel.log("[\(deviceInfo.name)] PointerSpeed: \(speedStr)")
                return
            }
        }
    }

    private func handleDiscoveryResponse(_ report: UnsafeBufferPointer<UInt8>) {
        let discoveredIndex = report[4]
        LogiDebugPanel.log("[\(deviceInfo.name)] IRoot response: discoveredIndex=\(String(format: "0x%02X", discoveredIndex))")
        if let (featureId, callback) = pendingDiscovery.first {
            discoveryTimer?.invalidate()
            pendingDiscovery.removeValue(forKey: featureId)
            callback(discoveredIndex == 0 ? nil : discoveredIndex)
        }
    }

    private func handleGetControlCountResponse(_ report: UnsafeBufferPointer<UInt8>) {
        reprogControlCount = Int(report[4])
        reprogQueryIndex = 0
        controlInfoRetryCounts.removeAll()
        discoveredControls.removeAll()
        LogiDebugPanel.log("[\(deviceInfo.name)] GetControlCount = \(reprogControlCount)")
        if reprogControlCount > 0, let idx = featureIndex[Self.featureReprogV4] {
            sendGetControlInfo(featureIndex: idx, index: 0)
        } else {
            // 设备声明 0 个可编程控件: discovery 走到终点, 记为握手完成.
            markHandshakeComplete()
            NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
            LogiSessionManager.shared.recomputeAndNotifyActivityState()
        }
    }

    private func handleGetControlInfoResponse(_ report: UnsafeBufferPointer<UInt8>) {
        guard report.count >= 11 else { return }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let taskId = (UInt16(report[6]) << 8) | UInt16(report[7])
        let flags1 = report[8]
        let flags2: UInt8 = report.count > 12 ? report[12] : 0
        let flags = UInt16(flags1) | (UInt16(flags2) << 8)
        // Solaar: bit 4 = reprogrammable (0x10), bit 5 = divertable (0x20)
        let isDivertable = (flags & 0x20) != 0

        discoveredControls.append(ControlInfo(cid: cid, taskId: taskId, flags: flags, isDivertable: isDivertable))
        LogiDebugPanel.log("[\(deviceInfo.name)] Control[\(reprogQueryIndex)]: CID=\(String(format: "0x%04X", cid)) flags=\(String(format: "0x%04X", flags)) divertable=\(isDivertable)")

        advanceControlInfoQuery()
    }

    // MARK: - GetControlReporting Query (function 2)

    /// 重跑 GetControlReporting 循环,刷新所有 control 的 reportingFlags / targetCID.
    /// 用于 UI 轮询冲突状态时调用(通过 LogiSessionManager.refreshReportingStates 节流).
    /// 不重新发现 feature / control,开销小(只是 N 个 HID++ 请求).
    /// 前提:初始 discovery 必须已完成;否则无 featureIndex / discoveredControls,直接跳过.
    /// 进行中(timer 未 nil)也跳过,避免 reportingQueryIndex 被重置导致错位.
    func refreshReportingState() {
        guard connectionMode != .unsupported,
              currentReceiverTargetIsConnected,
              !discoveredControls.isEmpty,
              featureIndex[Self.featureReprogV4] != nil else { return }
        if reportingQueryTimer != nil { return }
        LogiDebugPanel.log("[\(deviceInfo.name)] Refreshing reporting state (throttled)")
        startReportingQuery()
    }

    /// 开始逐个查询按键的 reporting 状态
    private func startReportingQuery() {
        pendingBLEUndivertGuardQueries.removeAll()
        reportingQueryIndex = 0
        for index in discoveredControls.indices {
            discoveredControls[index].reportingQueried = false
        }
        guard !discoveredControls.isEmpty, let idx = featureIndex[Self.featureReprogV4] else {
            divertBoundControls()
            // 镜像 advanceReportingQuery 正常终态: 即使 controls 为空也必须 post,
            // 否则 Self-Test Wizard 的 "wait reportingDidComplete" 会无限挂起.
            NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
            LogiSessionManager.shared.recomputeAndNotifyActivityState()
            return
        }
        LogiDebugPanel.log("[\(deviceInfo.name)] Querying reporting state for \(discoveredControls.count) controls...")
        sendGetControlReporting(featureIndex: idx, controlIndex: 0)
        // timer 刚被创建, 通知 Manager 汇总 activity 状态 (幂等, 无变化时不 post)
        LogiSessionManager.shared.recomputeAndNotifyActivityState()
    }

    private func sendGetControlReporting(featureIndex: UInt8, controlIndex: Int) {
        guard controlIndex < discoveredControls.count else { return }
        let cid = discoveredControls[controlIndex].cid
        // GetControlReporting: function 2, params: CID(2)
        sendRequest(featureIndex: featureIndex, functionId: 2,
                    params: [UInt8(cid >> 8), UInt8(cid & 0xFF)])
        scheduleReportingTimeout(index: controlIndex)
    }

    private func scheduleReportingTimeout(index: Int) {
        reportingQueryTimer?.invalidate()
        reportingQueryTimer = Timer.scheduledTimer(withTimeInterval: Self.reprogQueryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            LogiDebugPanel.log("[\(self.deviceInfo.name)] GetControlReporting[\(index)] timed out, skipping")
            self.advanceReportingQuery()
        }
    }

    /// 推进 reporting 查询 (正常响应 / 错误 / 超时 都调此方法)
    private func advanceReportingQuery() {
        reportingQueryTimer?.invalidate()
        reportingQueryTimer = nil
        reportingQueryIndex += 1
        if reportingQueryIndex < discoveredControls.count, let reprogIdx = featureIndex[Self.featureReprogV4] {
            sendGetControlReporting(featureIndex: reprogIdx, controlIndex: reportingQueryIndex)
        } else {
            LogiDebugPanel.log("[\(deviceInfo.name)] Reporting query complete")
            divertBoundControls()
            // 先让 divertBoundControls 置 reprogInitComplete=true / handshakeComplete=true, 再通知
            // 观察者, 避免 main-queue observer 在状态翻转前就读到 stale 值.
            NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
            // reportingQueryTimer 此时已 nil, 若 discoveryInFlight 也为 false 则 activity 真正结束.
            LogiSessionManager.shared.recomputeAndNotifyActivityState()
        }
    }

    private func handleGetControlReportingResponse(_ report: UnsafeBufferPointer<UInt8>) {
        guard let response = Self.parseReportingResponse(report) else { return }
        let expectedCID = reportingQueryIndex < discoveredControls.count
            ? discoveredControls[reportingQueryIndex].cid
            : nil
        let matchesExpectedCID = expectedCID == response.cid

        updateDiscoveredControlReportingState(response, markQueried: matchesExpectedCID)

        let cidName = LogiCIDDirectory.name(forCID: response.cid)
        let flagParts: [String] = [
            (response.reportingFlags & 0x01) != 0 ? "tmpDivert" : nil,
            (response.reportingFlags & 0x02) != 0 ? "persistDivert" : nil,
            (response.reportingFlags & 0x04) != 0 ? "tmpRemap" : nil,
            (response.reportingFlags & 0x08) != 0 ? "persistRemap" : nil,
        ].compactMap { $0 }
        let flagStr = flagParts.isEmpty ? "none" : flagParts.joined(separator: ",")
        let targetStr = response.targetCID != response.cid && response.targetCID != 0
            ? " -> \(String(format: "0x%04X", response.targetCID))(\(LogiCIDDirectory.name(forCID: response.targetCID)))"
            : ""
        LogiDebugPanel.log("[\(deviceInfo.name)] Reporting[\(cidName)]: flags=\(flagStr)\(targetStr)")

        guard matchesExpectedCID else {
            let expected = expectedCID.map { String(format: "0x%04X", $0) } ?? "none"
            LogiDebugPanel.log("[\(deviceInfo.name)] Stale GetControlReporting response for 0x\(String(format: "%04X", response.cid)) dropped (expected \(expected))")
            return
        }

        // 继续查询下一个 (或完成)
        advanceReportingQuery()
    }

    private func handleSetControlReportingAck(_ report: UnsafeBufferPointer<UInt8>) {
        guard let ack = Self.parseSetControlReportingAck(report) else { return }
        let isOwnAck = consumePendingSetControlReportingAck(ack)
        #if DEBUG
        LogiTrace.log(
            "[Session] handle SetReporting ACK cid=\(String(format: "0x%04X", ack.cid)) flags=\(String(format: "0x%02X", ack.flagsByte)) target=\(String(format: "0x%04X", ack.targetCID)) own=\(isOwnAck) lastApplied=\(LogiTrace.cids(lastApplied)) diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
        guard let cid = Self.reassertionCIDForSetControlReportingAck(
            lastApplied: lastApplied,
            divertedCIDs: divertedCIDs,
            ack: ack,
            isOwnAck: isOwnAck
        ) else {
            #if DEBUG
            LogiTrace.log("[Session] SetReporting ACK did not imply external clear", device: deviceInfo.name)
            #endif
            return
        }

        handleExternallyClearedDivert(cid: cid, reason: "SetControlReporting ACK")
    }

    private func handleReportingStateNotification(_ report: UnsafeBufferPointer<UInt8>) {
        guard let state = Self.parseReportingStateNotification(report) else { return }
        updateDiscoveredControlReportingState(state, markQueried: true)
        #if DEBUG
        LogiTrace.log(
            "[Session] reporting notification cid=\(String(format: "0x%04X", state.cid)) flags=\(String(format: "0x%02X", state.reportingFlags)) target=\(String(format: "0x%04X", state.targetCID)) lastApplied=\(LogiTrace.cids(lastApplied)) diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
        if handleStandardButtonGuardState(state, reason: "native-first reporting notification") {
            return
        }
        guard let cid = Self.reassertionCIDForReportingState(
                lastApplied: lastApplied,
                divertedCIDs: divertedCIDs,
                state: state
              ) else {
            #if DEBUG
            LogiTrace.log("[Session] reporting notification did not imply external clear", device: deviceInfo.name)
            #endif
            return
        }

        handleExternallyClearedDivert(cid: cid, reason: "reporting notification")
    }

    private func handleExternallyClearedDivert(cid: UInt16, reason: String) {
        #if DEBUG
        LogiTrace.log(
            "[Session] external clear detected reason=\(reason) cid=\(String(format: "0x%04X", cid)) before lastApplied=\(LogiTrace.cids(lastApplied)) diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
        lastApplied.remove(cid)
        divertedCIDs.remove(cid)
        releaseActiveButtonState(for: [cid], reason: "divert cleared externally")
        let mode = LogiSessionManager.shared.recordExternalClear(for: ownershipKey(forCID: cid))
        guard Self.shouldReassertAfterExternalClear(mode: mode) else {
            LogiDebugPanel.log("[\(deviceInfo.name)] External \(reason) cleared divert for \(String(format: "0x%04X", cid)); reassert suspended (\(mode.debugLabel))")
            return
        }
        LogiDebugPanel.log("[\(deviceInfo.name)] External \(reason) cleared divert for \(String(format: "0x%04X", cid)); scheduling reassert")
        scheduleDivertReassertion()
    }

    private static func shouldReassertAfterExternalClear(mode: LogiButtonDeliveryMode) -> Bool {
        return shouldUseHIDPPDelivery(mode: mode)
    }

    #if DEBUG
    internal static func shouldReassertAfterExternalClearForTests(mode: LogiButtonDeliveryMode) -> Bool {
        return shouldReassertAfterExternalClear(mode: mode)
    }
    #endif

    private func scheduleDivertReassertion() {
        guard divertReassertionWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.divertReassertionWorkItem = nil
            self.reassertDesiredDiverts()
        }
        divertReassertionWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.divertReassertionDelay, execute: item)
    }

    private func reassertDesiredDiverts() {
        guard reprogInitComplete,
              currentReceiverTargetIsConnected,
              featureIndex[Self.featureReprogV4] != nil else {
            #if DEBUG
            LogiTrace.log(
                "[Session] reassertDesiredDiverts skipped reprogInit=\(reprogInitComplete) connected=\(currentReceiverTargetIsConnected) hasReprog=\(featureIndex[Self.featureReprogV4] != nil)",
                device: deviceInfo.name
            )
            #endif
            return
        }

        #if DEBUG
        LogiTrace.log("[Session] reassertDesiredDiverts recording=\(LogiCenter.shared.isRecording)", device: deviceInfo.name)
        #endif
        if LogiCenter.shared.isRecording {
            temporarilyDivertAll()
        } else {
            primeFromRegistry()
        }
    }

    /// 初始化完成后: 按 binding 状态 divert 对应按键.
    /// 不再扫全部 divertable 控件 - 避免覆盖 Logitech Options+ 等第三方进程的 divert 设置.
    /// 跨启动残留: 本进程 Set 为空, 仅能处理当前 bound CID; 曾绑定但已解绑的残留依赖设备断电/重连自然清除 (tmpDivert 固件态).
    private func divertBoundControls() {
        reconcileAppliedDivertsWithQueriedState()
        reprogInitComplete = true
        handshakeComplete = true
        setDiscoveryInFlight(false)
        #if DEBUG
        LogiTrace.log("[Session] divertBoundControls prime registry discovered=\(discoveredControls.count)", device: deviceInfo.name)
        #endif
        primeFromRegistry()
        LogiDebugPanel.log("[\(deviceInfo.name)] Init complete, listening for button events")
    }

    private var queriedControlStates: [QueriedControlState] {
        return discoveredControls.map {
            QueriedControlState(
                cid: $0.cid,
                reportingFlags: $0.reportingFlags,
                reportingQueried: $0.reportingQueried
            )
        }
    }

    private func reconcileAppliedDivertsWithQueriedState() {
        let result = Self.reconciledDivertState(
            lastApplied: lastApplied,
            divertedCIDs: divertedCIDs,
            queriedControls: queriedControlStates
        )
        guard !result.lostCIDs.isEmpty else { return }

        releaseActiveButtonState(for: result.lostCIDs, reason: "divert lost")
        lastApplied = result.lastApplied
        divertedCIDs = result.divertedCIDs
        for cid in result.lostCIDs.sorted() {
            let mode = LogiSessionManager.shared.recordExternalClear(for: ownershipKey(forCID: cid))
            LogiDebugPanel.log(
                "[\(deviceInfo.name)] Reconciled lost divert state for CID \(String(format: "0x%04X", cid)); delivery=\(mode.debugLabel)"
            )
        }
    }

    private static func reconciledDivertState(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        queriedControls: [QueriedControlState]
    ) -> (lastApplied: Set<UInt16>, divertedCIDs: Set<UInt16>, lostCIDs: Set<UInt16>) {
        let lostCIDs = Set(queriedControls.compactMap { control -> UInt16? in
            guard lastApplied.contains(control.cid),
                  control.reportingQueried,
                  (control.reportingFlags & 0x01) == 0 else {
                return nil
            }
            return control.cid
        })

        return (
            lastApplied: lastApplied.subtracting(lostCIDs),
            divertedCIDs: divertedCIDs.subtracting(lostCIDs),
            lostCIDs: lostCIDs
        )
    }

    #if DEBUG
    internal static func reconciledDivertStateForTests(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        queriedControls: [QueriedControlState]
    ) -> (lastApplied: Set<UInt16>, divertedCIDs: Set<UInt16>) {
        let result = reconciledDivertState(
            lastApplied: lastApplied,
            divertedCIDs: divertedCIDs,
            queriedControls: queriedControls
        )
        return (lastApplied: result.lastApplied, divertedCIDs: result.divertedCIDs)
    }
    #endif

    /// 录制模式: 临时 divert 所有 divertable 按键
    func temporarilyDivertAll() {
        guard let idx = featureIndex[Self.featureReprogV4] else { return }
        guard currentReceiverTargetIsConnected else { return }
        let divertable = Set(discoveredControls.filter { $0.isDivertable }.map { $0.cid })
        let plan = Self.recordingDivertPlan(
            divertableCIDs: divertable,
            lastApplied: lastApplied,
            transport: LogiTransportIdentity(connectionMode),
            policy: LogiButtonDeliveryPolicy.default
        )
        #if DEBUG
        LogiTrace.log(
            "[Session] temporarilyDivertAll divertable=\(LogiTrace.cids(divertable)) desired=\(LogiTrace.cids(plan.desired)) toDivert=\(LogiTrace.cids(plan.toDivert)) toUndivert=\(LogiTrace.cids(plan.toUndivert)) beforeLastApplied=\(LogiTrace.cids(lastApplied))",
            device: deviceInfo.name
        )
        #endif
        releaseActiveButtonState(for: plan.toUndivert, reason: "recording uses native mouse events")
        for cid in plan.toDivert.sorted() {
            setControlReporting(featureIndex: idx, cid: cid, divert: true)
        }
        for cid in plan.toUndivert.sorted() {
            setControlReporting(featureIndex: idx, cid: cid, divert: false)
        }
        // Sync lastApplied with the recording target set so restoreDivertToBindings'
        // applyUsage diff (toUndivert = lastApplied - targetCIDs) can correctly
        // compute toUndivert for recording-only HID++ CIDs after recording ends.
        self.lastApplied = plan.desired
        LogiDebugPanel.log("[\(deviceInfo.name)] Temporarily diverted \(plan.desired.count)/\(divertable.count) controls (recording mode)")
    }

    /// 录制结束: 恢复到只 divert 有绑定的状态
    func restoreDivertToBindings() {
        #if DEBUG
        LogiTrace.log("[Session] restoreDivertToBindings via registry", device: deviceInfo.name)
        #endif
        primeFromRegistry()
    }

    private func handleDivertedButtonEvent(_ report: UnsafeBufferPointer<UInt8>) {
        var activeCIDs: Set<UInt16> = []
        var offset = 4
        while offset + 1 < report.count {
            let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
            if cid == 0 { break }
            activeCIDs.insert(cid)
            offset += 2
        }
        #if DEBUG
        let previousCIDs = buttonStateTracker.activeCIDs
        LogiDebugPanel.log(
            device: deviceInfo.name,
            type: .buttonEvent,
            message: "Button RAW: active=\(debugCIDList(activeCIDs)) previous=\(debugCIDList(previousCIDs)) report=\(debugReportBytes(report))"
        )
        #endif
        let delta = buttonStateTracker.update(activeCIDs: activeCIDs)
        #if DEBUG
        LogiDebugPanel.log(
            device: deviceInfo.name,
            type: .buttonEvent,
            message: "Button DELTA: pressed=\(debugCIDList(delta.pressed)) released=\(debugCIDList(delta.released)) now=\(debugCIDList(buttonStateTracker.activeCIDs))"
        )
        #endif
        for cid in delta.pressed {
            let cidName = LogiCIDDirectory.name(forCID: cid)
            LogiDebugPanel.log(device: deviceInfo.name, type: .buttonEvent, message: "Button DOWN: CID \(String(format: "0x%04X", cid)) (\(cidName))")
            dispatchButtonEvent(cid: cid, isDown: true)
        }
        for cid in delta.released {
            let cidName = LogiCIDDirectory.name(forCID: cid)
            LogiDebugPanel.log(device: deviceInfo.name, type: .buttonEvent, message: "Button UP: CID \(String(format: "0x%04X", cid)) (\(cidName))")
            dispatchButtonEvent(cid: cid, isDown: false)
        }
    }

    #if DEBUG
    private func debugCIDList(_ cids: Set<UInt16>) -> String {
        guard !cids.isEmpty else { return "[]" }
        let values = cids.sorted().map { cid in
            "\(String(format: "0x%04X", cid))(\(LogiCIDDirectory.name(forCID: cid)))"
        }
        return "[\(values.joined(separator: ","))]"
    }

    private func debugReportBytes(_ report: UnsafeBufferPointer<UInt8>) -> String {
        report.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func debugDispatchResultLabel(_ result: LogiDispatchResult) -> String {
        switch result {
        case .consumed:
            return "consumed"
        case .unhandled:
            return "unhandled"
        case .logiAction(let name):
            return "logiAction(\(name))"
        }
    }
    #endif

    // MARK: - Event Dispatch

    /// Emit synthetic releases when Mos changes divert/session ownership and a
    /// physical release may never arrive. Route through normal dispatch so
    /// mouse mappings, virtual modifiers, and Mos Scroll all unwind together.
    private func releaseAllActiveButtonState(reason: String) {
        emitSyntheticButtonReleases(
            for: buttonStateTracker.releaseAll(),
            reason: reason
        )
    }

    private func releaseActiveButtonState(for cids: Set<UInt16>, reason: String) {
        emitSyntheticButtonReleases(
            for: buttonStateTracker.releaseActiveCIDs(in: cids),
            reason: reason
        )
    }

    private func emitSyntheticButtonReleases(for cids: Set<UInt16>, reason: String) {
        for cid in cids.sorted() {
            let cidName = LogiCIDDirectory.name(forCID: cid)
            LogiDebugPanel.log(
                device: deviceInfo.name,
                type: .buttonEvent,
                message: "Synthetic Button UP: CID \(String(format: "0x%04X", cid)) (\(cidName)) [\(reason)]"
            )
            dispatchButtonEvent(cid: cid, isDown: false)
        }
    }

    private func dispatchButtonEvent(cid: UInt16, isDown: Bool) {
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)
        let event = InputEvent(
            type: .mouse,
            code: LogiCIDDirectory.toMosCode(cid),
            modifiers: currentFlags,
            phase: isDown ? .down : .up,
            source: .hidPP,
            device: deviceInfo
        )

        // Always-fired raw event (deterministic for wizard + debug observers)
        NotificationCenter.default.post(
            name: LogiCenter.rawButtonEvent,
            object: nil,
            userInfo: [
                "event": event,
                "mosCode": event.code,
                "cid": cid,
                "phase": isDown ? "down" : "up",
            ])

        let bridge = LogiCenter.shared.externalBridge

        if LogiCenter.shared.isRecording {
            let result = bridge.dispatchLogiButtonEvent(event)
            #if DEBUG
            LogiDebugPanel.log(
                device: deviceInfo.name,
                type: .buttonEvent,
                message: "Button DISPATCH: CID \(String(format: "0x%04X", cid)) code=\(event.code) phase=\(isDown ? "down" : "up") recording result=\(debugDispatchResultLabel(result))"
            )
            #endif
            return
        }

        // Side path: scroll hotkey fires regardless of binding outcome.
        bridge.handleLogiScrollHotkey(code: event.code, phase: event.phase)

        // Main routing.
        let result = bridge.dispatchLogiButtonEvent(event)
        #if DEBUG
        LogiDebugPanel.log(
            device: deviceInfo.name,
            type: .buttonEvent,
            message: "Button DISPATCH: CID \(String(format: "0x%04X", cid)) code=\(event.code) phase=\(isDown ? "down" : "up") result=\(debugDispatchResultLabel(result))"
        )
        #endif
        switch result {
        case .logiAction(let name) where event.phase == .down:
            executeLogiAction(name)
        case .consumed, .unhandled, .logiAction:
            break
        }
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
            LogiDebugPanel.log("[\(deviceInfo.name)] Unknown Logi action: \(name)")
        }
    }
}
