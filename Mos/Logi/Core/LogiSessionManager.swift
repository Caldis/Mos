//
//  LogiSessionManager.swift
//  Mos
//  Logitech HID 设备管理器 - 通过 IOKit 枚举和监控 Logitech 设备
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation
import IOKit
import IOKit.hid

/// Cycle direction for DPI / SmartShift toggle helpers.
public enum Direction { case up, down }

/// Internal manager that orchestrates Logi HID device sessions. The only
/// supported public surface is `LogiCenter` (Step 5's lint script enforces
/// this against the rest of the app). Tests in `MosTests/Logi*Tests.swift`
/// reference internal Logi symbols by design.
internal class LogiSessionManager {
    internal static let shared = LogiSessionManager()
    init() { NSLog("Module initialized: LogiSessionManager") }

    // MARK: - Constants
    static let logitechVendorId: Int = 0x046D
    static let buttonEventNotification = NSNotification.Name("LogiButtonEvent")

    // MARK: - State
    private var hidManager: IOHIDManager?
    private var sessions: [IOHIDDevice: LogiDeviceSession] = [:]
    private(set) var isActive = false
    private let deliveryModes = LogiButtonDeliveryModeStore()

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }
        LogiDebugPanel.log("[LogitechHID] Starting")

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            LogiDebugPanel.log("[LogitechHID] Failed to create IOHIDManager")
            return
        }

        // 只匹配 Logitech 设备
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: LogiSessionManager.logitechVendorId
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        // 注册回调 (使用 C 函数指针 + context)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemovedCallback, context)

        // Schedule 到 main RunLoop (HID++ 事件低频, 避免线程同步)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            LogiDebugPanel.log("[LogitechHID] Failed to open IOHIDManager: \(String(format: "0x%08x", result))")
            return
        }

        isActive = true
        LogiDebugPanel.log("[LogitechHID] Started")
    }

    func stop() {
        guard isActive else { return }
        LogiDebugPanel.log("[LogitechHID] Stopping")

        // 清理所有设备会话
        for (_, session) in sessions {
            session.teardown()
        }
        sessions.removeAll()

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        hidManager = nil
        isActive = false
        // sessions 被清空后重算一次, 把 lastKnownBusy 归位并让 UI 同步关闭 spinner.
        recomputeAndNotifyActivityState()
        LogiDebugPanel.log("[LogitechHID] Stopped")
    }

    // MARK: - Device Callbacks (C function pointers)

    private static let deviceMatchedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let manager = Unmanaged<LogiSessionManager>.fromOpaque(context).takeUnretainedValue()
        manager.deviceConnected(device)
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let manager = Unmanaged<LogiSessionManager>.fromOpaque(context).takeUnretainedValue()
        manager.deviceDisconnected(device)
    }

    // MARK: - Device Management

    private func deviceConnected(_ device: IOHIDDevice) {
        // 读取设备信息
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productId = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"

        LogiDebugPanel.log("[LogitechHID] Device connected: \(productName) (VID: \(String(format: "0x%04X", vendorId)), PID: \(String(format: "0x%04X", productId)))")

        // 避免重复会话
        guard sessions[device] == nil else { return }

        // 创建会话
        let session = LogiDeviceSession(hidDevice: device)
        sessions[device] = session
        session.setup()
        NotificationCenter.default.post(name: Self.sessionChangedNotification, object: nil)
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        guard let session = sessions.removeValue(forKey: device) else { return }
        LogiDebugPanel.log("[LogitechHID] Device disconnected: \(session.deviceInfo.name)")
        deliveryModes.removeModes(forDeviceNamed: session.deviceInfo.name, productId: session.deviceInfo.productId)
        session.teardown()
        NotificationCenter.default.post(name: Self.sessionChangedNotification, object: nil)
        // 断开的 session 可能曾处于 busy 状态, 重新聚合一次防止 spinner 卡住.
        recomputeAndNotifyActivityState()
    }

    // MARK: - Query

    /// 获取当前已连接的 Logitech 设备列表
    var connectedDevices: [InputDevice] {
        return sessions.values.map { $0.deviceInfo }
    }

    /// Debug: 暴露活跃的设备会话
    var activeSessions: [LogiDeviceSession] {
        return Array(sessions.values)
    }

    static let sessionChangedNotification = NSNotification.Name("LogiSessionChanged")

    /// 某个 session 的 discovery 握手流程开始或结束时触发; UI 据此切换 spinner.
    static let discoveryStateDidChangeNotification = NSNotification.Name("LogiDiscoveryStateDidChange")

    /// 某个 session 完成 reporting 查询后触发, UI 可据此刷新冲突指示.
    static let reportingQueryDidCompleteNotification = NSNotification.Name("LogiReportingQueryDidComplete")

    /// 任一 HID++ session 的活动状态 (discovery / reporting query) 发生变化时触发;
    /// 聚合后只在 "全局是否忙碌" 翻转的瞬间 post, UI 订阅后用来驱动 activity spinner.
    static let activityStateDidChangeNotification = NSNotification.Name("LogiActivityStateDidChange")

    /// 冲突状态变化通知; Step 4/5 会在 reporting query 完成等位置 post 此通知.
    /// Step 2 仅声明命名,不在任何位置 post.
    static let conflictChangedNotification = NSNotification.Name("LogiConflictChanged")

    // MARK: - Activity State Aggregation

    /// 最近一次已广播的聚合忙碌状态. 仅用于去抖 (transition-only post).
    private var lastKnownBusy: Bool = false

    /// 当前是否有任一 Logi session 正在执行 HID++ 交互 (discovery 或 reporting query).
    /// UI 在 main thread 同步读此值, 零阻塞.
    var isBusy: Bool { lastKnownBusy }

    /// 由 session 在活动状态变化的关键位置调用 (setDiscoveryInFlight / startReportingQuery /
    /// advanceReportingQuery 完成分支 / session 增删). Manager 聚合所有 session, 仅在全局
    /// 忙碌状态翻转时广播 `activityStateDidChangeNotification`.
    /// 调用链完全在 main thread (IOHIDManager 调度到 main RunLoop), 无需额外同步.
    func recomputeAndNotifyActivityState() {
        let newBusy = sessions.values.contains(where: { $0.isActivityInProgress })
        guard newBusy != lastKnownBusy else { return }
        lastKnownBusy = newBusy
        NotificationCenter.default.post(name: Self.activityStateDidChangeNotification, object: nil)
    }

    /// UI hover popover 的数据源: 所有当前活跃 session 的状态快照.
    /// popover 在可见时以低频 (~250ms) 拉取此快照而非订阅细粒度通知, 避免
    /// reporting query 每次 advance 都产生 post 导致通知风暴.
    var currentActivitySummary: [SessionActivityStatus] {
        return sessions.values.compactMap { $0.activityStatus }
    }

    // MARK: - Reporting Refresh Throttle

    /// 最小刷新间隔:避免 UI 事件频繁触发导致 HID++ 协议压力.
    /// 用户的预期场景 (打开面板 / 切分页 / App 激活) 在 10s 内几乎不会产生新的冲突变化,
    /// 取 10s 是响应性 vs HID link 稳定性的折中.
    private static let reportingRefreshMinInterval: TimeInterval = 10

    private var lastReportingRefresh: Date?

    /// Coalesced 入口:刷新所有 HID++ session 的 reporting 状态 (重跑 GetControlReporting).
    /// 调用方决定时机 (例如 UI 想看冲突图标), manager 只负责执行 + 节流.
    ///
    /// 节流: `reportingRefreshMinInterval` (~3s) 内重复调用直接返回, 防 UI 抖动.
    /// 没 Logi 候选会话时自然 no-op (sessions filter 后为空集合).
    /// 同步返回, 不阻塞 UI — 实际 HID++ 请求在各自 session 的 input-report 回调里
    /// 异步处理, 完成后通过 `reportingQueryDidCompleteNotification` 刷新 indicator.
    func refreshReportingStates() {
        if let last = lastReportingRefresh,
           Date().timeIntervalSince(last) < Self.reportingRefreshMinInterval {
            #if DEBUG
            LogiTrace.log("[Manager] refreshReportingStates throttled")
            #endif
            return
        }
        lastReportingRefresh = Date()
        #if DEBUG
        LogiTrace.log("[Manager] refreshReportingStates sessions=\(sessions.count)")
        #endif
        for session in sessions.values where session.isHIDPPCandidate {
            session.refreshReportingState()
        }
    }

    /// 查询某 Logi MosCode 当前是否被第三方 (如 Logitech Options+) 接管.
    /// 未连接设备 / 未完成 reporting 查询 / 非 Logi code -> unknown.
    func conflictStatus(forMosCode mosCode: UInt16) -> ConflictStatus {
        return buttonCaptureDiagnosis(forMosCode: mosCode).ownership
    }

    func buttonCaptureDiagnosis(forMosCode mosCode: UInt16) -> LogiButtonCaptureDiagnosis {
        guard let cid = LogiCIDDirectory.toCID(mosCode) else {
            return .unknown(nativeMouseButton: nil)
        }
        let nativeMouseButton = LogiCIDDirectory.nativeMouseButton(forCID: cid)
        var diagnoses: [LogiButtonCaptureDiagnosis] = []

        for session in sessions.values.sorted(by: Self.prefersDiagnosisSession) where session.isHIDPPCandidate {
            if let control = session.control(forCID: cid) {
                let mosOwns = session.debugDivertedCIDs.contains(cid)
                let ownership = LogiConflictDetector.status(
                    reportingFlags: control.reportingFlags,
                    targetCID: control.targetCID,
                    cid: cid,
                    reportingQueried: control.reportingQueried,
                    mosOwnsDivert: mosOwns
                )
                let key = session.ownershipKey(forCID: cid)
                let delivery = deliveryModes.mode(for: key)
                let usesNativeEvents = !LogiButtonDeliveryPolicy.default.shouldUseHIDPPDelivery(
                    transport: key.transport,
                    cid: cid,
                    phase: .normal
                )
                let diagnosis = LogiButtonCaptureDiagnosis(
                    ownership: ownership,
                    delivery: delivery,
                    ownershipKey: key,
                    nativeMouseButton: nativeMouseButton,
                    usesNativeEvents: usesNativeEvents
                )
                diagnoses.append(diagnosis)
            }
        }
        return diagnoses.first ?? .unknown(nativeMouseButton: nativeMouseButton)
    }

    private static func prefersDiagnosisSession(_ lhs: LogiDeviceSession, _ rhs: LogiDeviceSession) -> Bool {
        return diagnosisSessionRank(lhs) < diagnosisSessionRank(rhs)
    }

    private static func diagnosisSessionRank(_ session: LogiDeviceSession) -> Int {
        return diagnosisSessionRank(
            transport: LogiTransportIdentity(session.connectionMode),
            receiverTargetConnected: session.debugCurrentReceiverTargetIsConnected
        )
    }

    private static func diagnosisSessionRank(
        transport: LogiTransportIdentity,
        receiverTargetConnected: Bool
    ) -> Int {
        switch transport {
        case .receiver:
            return receiverTargetConnected ? 0 : 3
        case .bleDirect:
            return 1
        case .unsupported:
            return 4
        }
    }

    #if DEBUG
    internal static func diagnosisSessionRankForTests(
        transport: LogiTransportIdentity,
        receiverTargetConnected: Bool
    ) -> Int {
        return diagnosisSessionRank(
            transport: transport,
            receiverTargetConnected: receiverTargetConnected
        )
    }
    #endif

    func deliveryMode(forMosCode mosCode: UInt16) -> LogiButtonDeliveryMode? {
        return deliveryModes.deliveryMode(forMosCode: mosCode, matching: activeOwnershipKeys)
    }

    func notifyConflictChanged() {
        NotificationCenter.default.post(name: Self.conflictChangedNotification, object: nil)
    }

    private var activeOwnershipKeys: [LogiOwnershipKey] {
        return sessions.values.flatMap { $0.ownershipKeysForKnownControls() }
    }

    func deliveryMode(for key: LogiOwnershipKey) -> LogiButtonDeliveryMode {
        return deliveryModes.mode(for: key)
    }

    @discardableResult
    func recordExternalClear(for key: LogiOwnershipKey, at now: Date = Date()) -> LogiButtonDeliveryMode {
        let previousMode = deliveryModes.mode(for: key)
        let mode = deliveryModes.recordExternalClear(for: key, at: now)
        #if DEBUG
        LogiTrace.log("[Manager] recordExternalClear key=\(key.name) cid=\(String(format: "0x%04X", key.cid)) transport=\(key.transport) previous=\(previousMode.debugLabel) current=\(mode.debugLabel)")
        #endif
        if mode != previousMode {
            LogiDebugPanel.log(
                device: key.name,
                type: .buttonEvent,
                message: "[DeliveryMode] changed cid=\(String(format: "0x%04X", key.cid)) mosCode=\(LogiCIDDirectory.toMosCode(key.cid)) transport=\(key.transport) previous=\(previousMode.debugLabel) current=\(mode.debugLabel)"
            )
            if mode == .contended {
                showDeliveryContentionToast(for: key)
            }
        }
        if mode != .hidpp {
            notifyConflictChanged()
        }
        return mode
    }

    private func showDeliveryContentionToast(for key: LogiOwnershipKey) {
        let messageKey: String
        if key.transport == .bleDirect,
           LogiCIDDirectory.nativeMouseButton(forCID: key.cid) != nil {
            messageKey = "logi_ble_contention_standard_mouse_alias_toast"
        } else {
            messageKey = "logi_hidpp_contention_toast"
        }
        let controlName = LogiCIDDirectory.name(forCID: key.cid)
        let message = String(format: NSLocalizedString(messageKey, comment: ""), controlName)
        LogiCenter.shared.externalBridge.showLogiToast(message, severity: .warning)
    }

    // MARK: - Divert Control

    /// 录制模式标志: 录制期间跳过动作执行, 只转发事件给 KeyRecorder
    private(set) var isRecording = false

    /// 录制模式: 临时 divert 所有按键
    func temporarilyDivertAll() {
        isRecording = true
        #if DEBUG
        LogiTrace.log("[Manager] beginRecording sessions=\(sessions.count) candidates=\(sessions.values.filter { $0.isHIDPPCandidate }.count)")
        #endif
        for (_, session) in sessions where session.isHIDPPCandidate {
            session.temporarilyDivertAll()
        }
    }

    /// 录制结束: 恢复到只 divert 有绑定的按键
    func restoreDivertToBindings() {
        isRecording = false
        #if DEBUG
        LogiTrace.log("[Manager] endRecording sessions=\(sessions.count) candidates=\(sessions.values.filter { $0.isHIDPPCandidate }.count)")
        #endif
        for (_, session) in sessions where session.isHIDPPCandidate {
            session.restoreDivertToBindings()
        }
    }

    // MARK: - Logi Action Execution

    /// 获取最佳活跃 session (优先已完成 init 的, 其次 BLE)
    private var primarySession: LogiDeviceSession? {
        // 优先: 已完成 init 的 session
        if let ready = sessions.values.first(where: { $0.isHIDPPCandidate && $0.debugReprogInitComplete }) {
            return ready
        }
        // 其次: BLE 候选
        if let ble = sessions.values.first(where: { $0.isHIDPPCandidate && $0.debugIsBLE }) {
            return ble
        }
        // 最后: 任意候选
        return sessions.values.first(where: { $0.isHIDPPCandidate })
    }

    /// SmartShift 切换: 读取当前模式, 取反
    func executeSmartShiftToggle() {
        guard let session = primarySession else { return }
        session.executeSmartShiftToggle()
    }

    /// DPI 循环
    func executeDPICycle(direction: Direction) {
        guard let session = primarySession else { return }
        session.executeDPICycle(direction: direction)
    }
}
