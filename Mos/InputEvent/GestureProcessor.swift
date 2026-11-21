//
//  GestureProcessor.swift
//  Mos
//  鼠标手势处理器 - 状态机实现
//  按下触发按键 + 移动鼠标 → 识别方向 → 执行绑定动作
//  Created by Claude on 2026/4/15.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - GestureProcessor

class GestureProcessor {

    static let shared = GestureProcessor()
    init() {
        NSLog("Module initialized: GestureProcessor")
        // 注册运动事件回调到 MouseInteractionSessionController
        MouseInteractionSessionController.shared.gestureMotionHandler = { [weak self] event in
            self?.handleMotionEvent(event)
        }
    }

    // MARK: - State Machine

    private enum State {
        case idle
        case pending(binding: GestureBinding, savedCGEventType: CGEventType, savedButtonCode: UInt16, cursorPosition: CGPoint, accumulatedDX: Double, accumulatedDY: Double)
        case active(binding: GestureBinding)
    }

    private var state: State = .idle

    /// 独立的滚轮累积值 — 与 motion 累积 (state 中的 DX/DY) 完全分离
    /// 进入 pending 时重置, 离开 pending (无论是激活还是取消) 时重置
    private var pendingScrollDY: Double = 0

    // MARK: - Binding Cache

    /// 缓存的手势绑定列表 (按触发优先级排序: modifier 数量多的优先)
    private var cachedBindings: [GestureBinding] = []
    private var isDirty = true

    /// 使缓存失效 (手势绑定更改后调用)
    func invalidateCache() {
        isDirty = true
    }

    private func refreshCacheIfNeeded() {
        guard isDirty else { return }
        cachedBindings = Options.shared.gestures.binding
            .filter { $0.isEnabled }
            .sorted { lhs, rhs in
                // modifier 数量多的排在前面 (更精确的匹配优先)
                let lhsMods = lhs.triggerEvent.modifiers
                let rhsMods = rhs.triggerEvent.modifiers
                return lhsMods.nonzeroBitCount > rhsMods.nonzeroBitCount
            }
        isDirty = false
    }

    // MARK: - Button Event Handling

    /// 处理按键/鼠标按下/抬起事件 (在 ButtonCore 中 InputProcessor 之前调用)
    /// - Returns: .consumed 表示事件已被手势系统处理, .passthrough 表示未匹配
    func handleButtonEvent(_ event: InputEvent, cgEvent: CGEvent) -> InputResult {
        switch state {
        case .idle:
            guard event.phase == .down else { return .passthrough }
            return handleDownInIdle(event: event, cgEvent: cgEvent)

        case .pending(let binding, let savedType, let savedCode, let cursorPos, let dx, let dy):
            if event.phase == .down {
                // 另一个按键按下时取消手势, 回放原始点击
                replayOriginalClick(eventType: savedType, buttonCode: savedCode, position: cursorPos)
                stopGestureTracking()
                pendingScrollDY = 0
                state = .idle
                return .passthrough
            } else {
                // Up 事件: 检查是否为触发按键的松开
                if event.type == binding.triggerEvent.type && event.code == binding.triggerEvent.code {
                    // 阈值未达到 → 回放原始点击
                    _ = dx; _ = dy
                    replayOriginalClick(eventType: savedType, buttonCode: savedCode, position: cursorPos)
                    stopGestureTracking()
                    pendingScrollDY = 0
                    state = .idle
                    return .consumed
                }
                return .passthrough
            }

        case .active(let binding):
            // 手势已激活: 等待触发按键松开
            if event.phase == .up &&
               event.type == binding.triggerEvent.type &&
               event.code == binding.triggerEvent.code {
                stopGestureTracking()
                state = .idle
                return .consumed
            }
            // 其他按键事件放行
            return event.phase == .down ? .passthrough : .passthrough
        }
    }

    // MARK: - Motion Event Handling

    /// 处理鼠标运动事件 (由 MouseInteractionSessionController 的 gestureMotionHandler 调用)
    /// 仅当绑定有 movement 动作时才会触发 motion tap, 故此处无需额外检查
    func handleMotionEvent(_ event: CGEvent) {
        guard case .pending(let binding, let savedType, let savedCode, let cursorPos, var dx, var dy) = state else {
            return
        }
        guard binding.hasAnyMovementAction else { return }

        // 累积 delta
        let deltaX = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let deltaY = Double(event.getIntegerValueField(.mouseEventDeltaY))
        dx += deltaX
        dy += deltaY

        // 更新 pending 状态中的累积值
        state = .pending(
            binding: binding,
            savedCGEventType: savedType,
            savedButtonCode: savedCode,
            cursorPosition: cursorPos,
            accumulatedDX: dx,
            accumulatedDY: dy
        )

        // 尝试识别方向
        if let direction = resolveDirection(dx: dx, dy: dy, threshold: binding.threshold) {
            // 方向确定 → 执行动作
            if let actionName = binding.action(for: direction), !actionName.isEmpty {
                ShortcutExecutor.shared.execute(named: actionName)
            }
            state = .active(binding: binding)
        }
    }

    // MARK: - Scroll Event Handling

    /// 处理滚轮事件 (由 ScrollCore.scrollEventCallBack 调用)
    /// Scroll 动作与 Movement 动作完全独立, 使用独立的 pendingScrollDY 累积器
    ///
    /// 消费规则 (防止"滚动冲突"):
    /// - 只消费该方向上有配置动作的滚轮事件; 无动作的方向立即放行, 正常滚动
    /// - 换向时重置累积器
    /// - active 状态: 仅消费有动作的方向 (防止意外平滑)
    ///
    /// Delta 读取优先级 (兼容离散 + 平滑滚轮):
    ///   fixedPt (浮点) → 整数行数; 跳过 pixel delta (单位不一致)
    ///
    /// - Returns: true 表示事件已被手势系统消费 (ScrollCore 应 return nil)
    func handleScrollEvent(_ event: CGEvent) -> Bool {
        switch state {
        case .pending(let binding, _, _, _, _, _):
            guard binding.hasAnyScrollAction else { return false }

            // 使用 fixedPt 浮点值 (兼容平滑滚轮), 回退到整数行数
            let fixedPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let rawDelta = fixedPt != 0.0
                ? fixedPt
                : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            guard rawDelta != 0 else { return false }

            // 轴1: 向上为负, 向下为正
            let eventDirection: GestureDirection = rawDelta < 0 ? .up : .down

            // 无动作的方向: 立即放行, 不积累 (防止该方向的滚动被吃掉)
            guard binding.scrollAction(for: eventDirection) != nil else {
                pendingScrollDY = 0
                return false
            }

            // 换向时重置累积器
            if pendingScrollDY != 0 && rawDelta * pendingScrollDY < 0 {
                pendingScrollDY = 0
            }
            pendingScrollDY += rawDelta

            if abs(pendingScrollDY) >= binding.scrollThreshold {
                if let actionName = binding.scrollAction(for: eventDirection), !actionName.isEmpty {
                    ShortcutExecutor.shared.execute(named: actionName)
                }
                pendingScrollDY = 0
                state = .active(binding: binding)
            }
            return true  // 消费: 正在向有动作的方向积累

        case .active(let binding):
            // 触发键仍持按中: scroll 手势可重复触发 (每次到达阈值即执行)
            // 无动作的方向仍正常放行; 有动作的方向继续消费并在阈值时重新执行
            let fixedPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let rawDelta = fixedPt != 0.0
                ? fixedPt
                : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            guard rawDelta != 0 else { return false }
            let direction: GestureDirection = rawDelta < 0 ? .up : .down

            guard binding.scrollAction(for: direction) != nil else { return false }

            if pendingScrollDY != 0 && rawDelta * pendingScrollDY < 0 {
                pendingScrollDY = 0
            }
            pendingScrollDY += rawDelta

            if abs(pendingScrollDY) >= binding.scrollThreshold {
                if let actionName = binding.scrollAction(for: direction), !actionName.isEmpty {
                    ShortcutExecutor.shared.execute(named: actionName)
                }
                pendingScrollDY = 0
            }
            return true

        case .idle:
            return false
        }
    }

    // MARK: - Direction Resolution

    /// 判断主导方向
    /// - 主轴 delta 绝对值需超过 threshold
    /// - 主轴 delta 绝对值需超过另一轴 delta 绝对值的 1.5 倍 (防止斜向误触)
    func resolveDirection(dx: Double, dy: Double, threshold: Double) -> GestureDirection? {
        let absDX = abs(dx)
        let absDY = abs(dy)
        let diagonalRatio = 1.5

        if absDX >= absDY {
            // 水平主导
            guard absDX >= threshold else { return nil }
            guard absDY == 0 || absDX / absDY >= diagonalRatio else { return nil }
            return dx > 0 ? .right : .left
        } else {
            // 垂直主导
            guard absDY >= threshold else { return nil }
            guard absDX == 0 || absDY / absDX >= diagonalRatio else { return nil }
            // CGEvent deltaY: 正值 = 鼠标向下移动
            return dy > 0 ? .down : .up
        }
    }

    // MARK: - Clear State

    /// 清空所有手势状态 (ButtonCore disable 时调用)
    func clearState() {
        state = .idle
        pendingScrollDY = 0
        stopGestureTracking()
    }

    // MARK: - Private Helpers

    private func handleDownInIdle(event: InputEvent, cgEvent: CGEvent) -> InputResult {
        refreshCacheIfNeeded()

        guard let binding = findMatchingBinding(for: event) else {
            return .passthrough
        }

        // 记录光标位置 (CGEvent 坐标: 左上角为原点)
        let cursorPosition = cgEvent.location

        // 推算触发按键对应的 CGEventType (用于回放)
        let savedCGEventType: CGEventType
        switch event.type {
        case .mouse:
            switch event.code {
            case 0:  savedCGEventType = .leftMouseDown
            case 1:  savedCGEventType = .rightMouseDown
            default: savedCGEventType = .otherMouseDown
            }
        case .keyboard:
            savedCGEventType = .keyDown
        }

        pendingScrollDY = 0
        state = .pending(
            binding: binding,
            savedCGEventType: savedCGEventType,
            savedButtonCode: event.code,
            cursorPosition: cursorPosition,
            accumulatedDX: 0,
            accumulatedDY: 0
        )

        // motion tap 只在有 movement 动作时才需要
        if binding.hasAnyMovementAction {
            startGestureTracking()
        }
        return .consumed
    }

    /// 查找最匹配的手势绑定 (优先级: modifier 数量最多的优先, 与 ButtonUtils 一致)
    /// 鼠标事件允许额外 modifier (用户可能在持握 modifier 键时按下触发按键)
    private func findMatchingBinding(for event: InputEvent) -> GestureBinding? {
        refreshCacheIfNeeded()
        var bestBinding: GestureBinding? = nil
        var bestPriority = -1
        for binding in cachedBindings {
            if let priority = binding.triggerEvent.matchPriority(for: event), priority > bestPriority {
                bestPriority = priority
                bestBinding = binding
            }
        }
        return bestBinding
    }

    /// 开始手势追踪 (通知 MouseInteractionSessionController 保持 motion tap 运行)
    private func startGestureTracking() {
        MouseInteractionSessionController.shared.setGestureTracking(true)
    }

    /// 停止手势追踪
    private func stopGestureTracking() {
        MouseInteractionSessionController.shared.setGestureTracking(false)
    }

    /// 回放原始鼠标点击 (手势阈值未达到时, 恢复原始按键行为)
    private func replayOriginalClick(eventType: CGEventType, buttonCode: UInt16, position: CGPoint) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // 确定 mouseButton 参数
        let mouseButton: CGMouseButton
        switch eventType {
        case .leftMouseDown:  mouseButton = .left
        case .rightMouseDown: mouseButton = .right
        default:              mouseButton = .center
        }

        // 发送 mouseDown 事件
        if let downEvent = CGEvent(mouseEventSource: source, mouseType: eventType, mouseCursorPosition: position, mouseButton: mouseButton) {
            if eventType == .otherMouseDown {
                downEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonCode))
            }
            downEvent.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
            downEvent.post(tap: .cghidEventTap)
        }

        // 确定对应的 mouseUp 事件类型
        let upEventType: CGEventType
        switch eventType {
        case .leftMouseDown:  upEventType = .leftMouseUp
        case .rightMouseDown: upEventType = .rightMouseUp
        default:              upEventType = .otherMouseUp
        }

        // 发送 mouseUp 事件
        if let upEvent = CGEvent(mouseEventSource: source, mouseType: upEventType, mouseCursorPosition: position, mouseButton: mouseButton) {
            if upEventType == .otherMouseUp {
                upEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonCode))
            }
            upEvent.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
            upEvent.post(tap: .cghidEventTap)
        }
    }
}
