//
//  LogiSessionEnvironment.swift
//  Mos
//  Session 上行能力的窄接口 (P5-6): LogiDeviceSession 不再反向引用
//  LogiSessionManager.shared / LogiCenter.shared, 全部上行调用经由此协议注入.
//  Created by Caldis on 2026/7/11.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

/// Session 需要的全部上行能力. 生产实现由组合根 LogiCenter 组装
/// (LogiSessionEnvironmentAdapter), 测试可注入替身, 使 session 及
/// 未来从它拆出的组件 (P5-1) 能脱离单例图实例化.
internal protocol LogiSessionEnvironment: AnyObject {
    /// 按键投递模式查询 (manager 的 LogiButtonDeliveryModeStore)
    func deliveryMode(for key: LogiOwnershipKey) -> LogiButtonDeliveryMode
    /// 记录一次外部清除 divert, 返回演进后的投递模式
    @discardableResult
    func recordExternalClear(for key: LogiOwnershipKey) -> LogiButtonDeliveryMode
    /// 活动状态 (discovery / reporting query) 变化终点: 聚合重算全局 busy
    func notifyActivityChanged()
    /// 录制模式: 录制期间按键事件只转发给 KeyRecorder, 不执行动作
    var isRecording: Bool { get }
    /// 绑定注册表是否存在任一绑定 (接管集合过滤用)
    var bindingsExist: Bool { get }
    /// 发现完成后, 让注册表按当前聚合绑定 prime 本 session 的 divert
    func primeBindings(for session: LogiDeviceSession)
    /// 外部桥: Toast 提示
    func showToast(_ message: String, severity: LogiToastSeverity)
    /// 外部桥: 按键事件分发 (绑定执行 / 录制转发)
    @discardableResult
    func dispatchButtonEvent(_ event: InputEvent) -> LogiDispatchResult
    /// 外部桥: 滚动热键旁路
    func handleScrollHotkey(code: UInt16, phase: InputPhase)
}

/// 生产实现: 把协议各能力路由到 manager / registry / 当前 bridge.
/// - manager 用 unowned: manager 持有注入了本 adapter 的 sessions, 强引用会成环
/// - bridge 用 provider 闭包而非快照: bridge 可被 installBridge 热替换, 必须读现值
internal final class LogiSessionEnvironmentAdapter: LogiSessionEnvironment {
    private unowned let manager: LogiSessionManager
    private let registry: UsageRegistry
    private let bridgeProvider: () -> LogiExternalBridge

    init(manager: LogiSessionManager,
         registry: UsageRegistry,
         bridgeProvider: @escaping () -> LogiExternalBridge) {
        self.manager = manager
        self.registry = registry
        self.bridgeProvider = bridgeProvider
    }

    func deliveryMode(for key: LogiOwnershipKey) -> LogiButtonDeliveryMode {
        return manager.deliveryMode(for: key)
    }

    @discardableResult
    func recordExternalClear(for key: LogiOwnershipKey) -> LogiButtonDeliveryMode {
        return manager.recordExternalClear(for: key)
    }

    func notifyActivityChanged() {
        manager.recomputeAndNotifyActivityState()
    }

    var isRecording: Bool { manager.isRecording }

    var bindingsExist: Bool { !registry.aggregatedCacheIsEmpty }

    func primeBindings(for session: LogiDeviceSession) {
        registry.primeSession(session)
    }

    func showToast(_ message: String, severity: LogiToastSeverity) {
        bridgeProvider().showLogiToast(message, severity: severity)
    }

    @discardableResult
    func dispatchButtonEvent(_ event: InputEvent) -> LogiDispatchResult {
        return bridgeProvider().dispatchLogiButtonEvent(event)
    }

    func handleScrollHotkey(code: UInt16, phase: InputPhase) {
        bridgeProvider().handleLogiScrollHotkey(code: code, phase: phase)
    }
}
