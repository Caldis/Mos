//
//  TiltWheelHandler.swift
//  Mos
//  倾斜滚轮虚拟按键处理器
//  Created by Claude on 2026/4/23.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

/// 将连续的水平滚轮事件流转换为离散的 down/up 生命周期，送入 InputProcessor 管线。
/// 支持类似键盘按键重复的行为：倾斜开始时立即触发 down，持续倾斜时按固定间隔重复触发 down，
/// 停止倾斜后触发 up。
///
/// 线程模型:
///   handle(xDelta:) 在 CGEventTap 回调线程调用。
///   synthesize / 所有计时器操作全部在主线程执行，activeCode 等状态仅在主线程访问。
class TiltWheelHandler {
    static let shared = TiltWheelHandler()
    private init() {}

    // 倾斜停止判定：最后一次事件后超过此时间则认为倾斜结束
    // 设为 60ms：确保连打间隔（通常 80~150ms 静默）能被准确识别为独立手势
    // 低于连续事件间隔（20~50ms），因此持续倾斜时不会误触发停止判定
    private static let stopInterval: TimeInterval = 0.060
    // 键位重复：首次重复前的初始延迟（仿 macOS 键盘重复行为）
    private static let repeatInitialDelay: TimeInterval = 0.400
    // 键位重复：后续重复间隔
    private static let repeatInterval: TimeInterval = 0.200
    // Shift/切换键冷却：释放后继续抑制的时间窗口，防止过渡期残留事件误触发
    private static let shiftCooldownInterval: TimeInterval = 0.150

    // MARK: - 主线程状态

    private var activeCode: UInt16?
    /// 停止检测计时器：最后一次事件后 stopInterval 无事件则触发 up
    private var stopTimer: Timer?
    /// 重复计时器：倾斜持续期间按 repeatInterval 重复触发 down
    private var repeatTimer: Timer?

    // MARK: - Shift/切换键抑制（从回调线程设置，Date 为值类型，赋值无并发风险）

    private var shiftSuppressedUntil: Date = .distantPast

    /// 检测到 Shift 或切换键活跃的水平滚动时调用，延长抑制窗口
    func notifyModifierActive() {
        shiftSuppressedUntil = Date().addingTimeInterval(TiltWheelHandler.shiftCooldownInterval)
    }

    private var isModifierSuppressed: Bool {
        return Date() < shiftSuppressedUntil
    }

    // MARK: - 事件过滤辅助 (ButtonCore 拦截回调与 KeyRecorder 录制共用)

    /// 判断是否为 Shift 修饰键或 toggleScroll 驱动的水平滚动 (应排除以避免误触发)
    static func isModifierDrivenHorizontalScroll(_ event: CGEvent) -> Bool {
        return event.flags.contains(.maskShift) || ScrollCore.shared.toggleScroll
    }

    /// 从滚轮事件中提取倾斜方向对应的虚拟键码
    /// 要求纯水平滚动 (xDelta != 0 且 yDelta == 0), 否则返回 nil
    static func tiltCode(for event: CGEvent) -> UInt16? {
        let xDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let yDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        guard xDelta != 0.0, yDelta == 0.0 else { return nil }
        return xDelta > 0 ? KeyCode.tiltRight : KeyCode.tiltLeft
    }

    // MARK: - 公开接口

    /// 由 ButtonCore 的 scrollWheel 拦截器回调调用（回调线程）。
    /// 返回 true 表示该方向有绑定，调用方应消费（返回 nil）该事件。
    func handle(code: UInt16) -> Bool {
        guard !isModifierSuppressed else { return false }
        let hasBinding = !ButtonUtils.shared.getButtonBindings(for: .mouse, code: code).isEmpty
        DispatchQueue.main.async { [weak self] in
            self?.synthesize(code: code)
        }
        return hasBinding
    }

    /// 清理所有进行中的状态。ButtonCore disable 时调用，防止状态残留。
    func clearState() {
        shiftSuppressedUntil = .distantPast
        if let code = activeCode {
            endTilt(code)
        }
    }

    // MARK: - 主线程私有逻辑

    private func synthesize(code: UInt16) {
        guard let current = activeCode else {
            beginTilt(code)
            return
        }
        if current == code {
            // 同方向持续倾斜：重置停止计时器，保持重复计时器运行
            resetStopTimer(for: code)
        } else {
            // 方向切换：结束旧手势，开始新手势
            endTilt(current)
            beginTilt(code)
        }
    }

    /// 开始新的倾斜手势：立即触发 down，启动重复和停止计时器
    private func beginTilt(_ code: UInt16) {
        activeCode = code
        fireInputEvent(code: code, phase: .down)
        startRepeatTimer(for: code)
        resetStopTimer(for: code)
    }

    /// 结束倾斜手势：取消计时器，触发 up
    private func endTilt(_ code: UInt16) {
        stopTimer?.invalidate()
        stopTimer = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        activeCode = nil
        fireInputEvent(code: code, phase: .up)
    }

    /// 重置停止检测计时器。每次收到同方向事件时调用，延迟判定倾斜结束。
    private func resetStopTimer(for code: UInt16) {
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: TiltWheelHandler.stopInterval, repeats: false) { [weak self] _ in
            guard let self = self, self.activeCode == code else { return }
            self.endTilt(code)
        }
    }

    /// 启动键位重复计时器：初始延迟后开始，之后按固定间隔触发 down。
    private func startRepeatTimer(for code: UInt16) {
        repeatTimer?.invalidate()
        // 初始延迟：等待 repeatInitialDelay 后开始重复
        repeatTimer = Timer.scheduledTimer(withTimeInterval: TiltWheelHandler.repeatInitialDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.activeCode == code else { return }
            self.fireInputEvent(code: code, phase: .down)
            // 切换为固定间隔重复
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: TiltWheelHandler.repeatInterval, repeats: true) { [weak self] _ in
                guard let self = self, self.activeCode == code else {
                    self?.repeatTimer?.invalidate()
                    return
                }
                self.fireInputEvent(code: code, phase: .down)
            }
        }
    }

    // MARK: - 事件发送

    private func fireInputEvent(code: UInt16, phase: InputPhase) {
        let modifiers = CGEventSource.flagsState(.combinedSessionState)
        let event = InputEvent(
            type: .mouse,
            code: code,
            modifiers: modifiers,
            phase: phase,
            source: .hidPP,
            device: nil
        )
        _ = InputProcessor.shared.process(event)
    }
}
