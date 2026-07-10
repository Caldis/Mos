//
//  MouseGestureTracker.swift
//  Mos
//  鼠标手势追踪器 - 按住鼠标按键并移动触发方向手势
//  Created by MiMoCode on 2026/6/12.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - GestureDirection
/// 手势方向
enum GestureDirection: String, CaseIterable {
    case up = "up"
    case down = "down"
    case left = "left"
    case right = "right"
    case upLeft = "upLeft"
    case upRight = "upRight"
    case downLeft = "downLeft"
    case downRight = "downRight"

    /// 方向对应的角度范围 (度, 0=右, 90=上)
    var angleRange: (min: Double, max: Double) {
        switch self {
        case .up:      return (67.5, 112.5)
        case .down:    return (247.5, 292.5)
        case .left:    return (157.5, 202.5)
        case .right:   return (-22.5, 22.5)
        case .upLeft:   return (112.5, 157.5)
        case .upRight:  return (22.5, 67.5)
        case .downLeft: return (202.5, 247.5)
        case .downRight: return (292.5, 337.5)
        }
    }

    /// 检查角度是否在此方向范围内
    func matches(angle: Double) -> Bool {
        let (min, max) = angleRange
        if min < 0 {
            // 跨越0度 (如 right)
            return angle >= min + 360 || angle <= max
        }
        return angle >= min && angle <= max
    }
}

// MARK: - GestureAction
/// 手势动作配置
struct GestureAction {
    let direction: GestureDirection
    let keyCode: UInt16
    let modifiers: CGEventFlags
    let description: String

    /// ESC 键
    static let escape = GestureAction(
        direction: .upLeft,
        keyCode: KeyCode.escape,
        modifiers: [],
        description: "ESC"
    )

    /// 刷新 (Cmd+R)
    static let refresh = GestureAction(
        direction: .up,
        keyCode: 15,  // R 键
        modifiers: .maskCommand,
        description: "Refresh (Cmd+R)"
    )
}

// MARK: - MouseGestureTracker
/// 鼠标手势追踪器
/// 单例模式, 跟踪按住鼠标按键时的移动并识别方向手势
class MouseGestureTracker {

    static let shared = MouseGestureTracker()
    private init() {}

    // MARK: - 配置

    /// 启用手势的鼠标按键 (1=右键)
    var gestureButton: Int = 1

    /// 最小触发距离 (像素)
    var minimumDistance: CGFloat = 30.0

    /// 启用的手势动作列表
    var enabledActions: [GestureAction] = [
        .escape,
        .refresh
    ]

    // MARK: - 状态

    /// 是否正在追踪手势
    private(set) var isTracking = false

    /// 按下时的起始位置
    private var startPoint: CGPoint = .zero

    /// 按下时的时间
    private var startTime: TimeInterval = 0

    /// 已触发的手势 (防止重复触发)
    private var triggeredDirection: GestureDirection?

    // MARK: - 公共方法

    /// 开始追踪 (鼠标按下时调用)
    func startTracking(at point: CGPoint) {
        startPoint = point
        startTime = Date.timeIntervalSinceReferenceDate
        isTracking = true
        triggeredDirection = nil
    }

    /// 更新追踪 (鼠标移动时调用)
    func updateTracking(at point: CGPoint) -> GestureDirection? {
        guard isTracking else { return nil }

        let deltaX = point.x - startPoint.x
        let deltaY = point.y - startPoint.y
        let distance = hypot(deltaX, deltaY)

        // 检查是否达到最小距离
        guard distance >= minimumDistance else { return nil }

        // 计算角度 (度, 0=右, 90=上, 逆时针)
        var angle = atan2(deltaY, deltaX) * 180.0 / .pi
        if angle < 0 { angle += 360.0 }

        // 确定方向
        for action in enabledActions {
            if action.direction.matches(angle: angle) {
                // 防止同一方向重复触发
                if triggeredDirection != action.direction {
                    triggeredDirection = action.direction
                    return action.direction
                }
            }
        }

        return nil
    }

    /// 停止追踪 (鼠标释放时调用)
    func stopTracking() {
        isTracking = false
        startPoint = .zero
        startTime = 0
        triggeredDirection = nil
    }

    /// 获取指定方向的动作
    func action(for direction: GestureDirection) -> GestureAction? {
        return enabledActions.first { $0.direction == direction }
    }

    /// 执行指定方向的手势动作
    func executeAction(for direction: GestureDirection) {
        guard let action = action(for: direction) else { return }

        // 发送按键事件
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let isModifierKey = KeyCode.modifierKeys.contains(action.keyCode)

        if isModifierKey {
            // 修饰键: 使用 flagsChanged 事件
            guard let event = CGEvent(source: source) else { return }
            event.type = .flagsChanged
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(action.keyCode))
            if action.modifiers.rawValue != 0 {
                event.flags = action.modifiers
            }
            event.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
            event.post(tap: .cghidEventTap)

            // 发送释放事件
            guard let upEvent = CGEvent(source: source) else { return }
            upEvent.type = .flagsChanged
            upEvent.setIntegerValueField(.keyboardEventKeycode, value: Int64(action.keyCode))
            upEvent.flags = CGEventFlags(rawValue: 0)
            upEvent.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
            upEvent.post(tap: .cghidEventTap)
        } else {
            // 普通键: 使用 keyDown/keyUp
            guard let downEvent = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: true) else { return }
            downEvent.flags = action.modifiers
            downEvent.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
            downEvent.post(tap: .cghidEventTap)

            guard let upEvent = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: false) else { return }
            upEvent.flags = action.modifiers
            upEvent.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
            upEvent.post(tap: .cghidEventTap)
        }

        NSLog("MouseGesture: Executed \(action.description) for direction \(direction.rawValue)")
    }
}
