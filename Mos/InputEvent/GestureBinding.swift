//
//  GestureBinding.swift
//  Mos
//  鼠标手势绑定数据结构
//  Created by Claude on 2026/4/15.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - GestureDirection

/// 手势方向
enum GestureDirection: String, Codable, CaseIterable {
    case up    = "up"
    case down  = "down"
    case left  = "left"
    case right = "right"

    /// 方向箭头符号 (用于 UI 显示)
    var arrowSymbol: String {
        switch self {
        case .up:    return "↑"
        case .down:  return "↓"
        case .left:  return "←"
        case .right: return "→"
        }
    }

    /// 本地化显示名称
    var localizedName: String {
        return NSLocalizedString(rawValue, comment: "")
    }
}

// MARK: - GestureBinding

/// 手势绑定 - 将录制的触发按键与四个方向的动作关联
/// 一个触发按键对应四个方向动作 (上/下/左/右), 每个方向可独立配置或留空
struct GestureBinding: Codable, Equatable {

    // MARK: - 持久化字段

    /// 唯一标识符
    let id: UUID

    /// 录制的触发事件 (哪个按键触发手势模式)
    let triggerEvent: RecordedEvent

    /// 上方向动作名称 (SystemShortcut identifier, nil = 无动作)
    var upAction: String?

    /// 下方向动作名称
    var downAction: String?

    /// 左方向动作名称
    var leftAction: String?

    /// 右方向动作名称
    var rightAction: String?

    /// 移动阈值 (像素), 超过后触发方向识别 (默认 30.0)
    var threshold: Double

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    let createdAt: Date

    // MARK: - 初始化

    init(
        id: UUID = UUID(),
        triggerEvent: RecordedEvent,
        upAction: String? = nil,
        downAction: String? = nil,
        leftAction: String? = nil,
        rightAction: String? = nil,
        threshold: Double = 30.0,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.triggerEvent = triggerEvent
        self.upAction = upAction
        self.downAction = downAction
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    // MARK: - 方向动作访问

    /// 获取指定方向的动作名称
    func action(for direction: GestureDirection) -> String? {
        switch direction {
        case .up:    return upAction
        case .down:  return downAction
        case .left:  return leftAction
        case .right: return rightAction
        }
    }

    /// 设置指定方向的动作名称 (返回更新后的副本)
    func withAction(_ action: String?, for direction: GestureDirection) -> GestureBinding {
        var copy = self
        switch direction {
        case .up:    copy.upAction = action
        case .down:  copy.downAction = action
        case .left:  copy.leftAction = action
        case .right: copy.rightAction = action
        }
        return copy
    }

    /// 是否有任意方向已配置动作
    var hasAnyAction: Bool {
        return upAction != nil || downAction != nil || leftAction != nil || rightAction != nil
    }

    // MARK: - Equatable

    static func == (lhs: GestureBinding, rhs: GestureBinding) -> Bool {
        return lhs.id == rhs.id &&
               lhs.triggerEvent == rhs.triggerEvent &&
               lhs.upAction == rhs.upAction &&
               lhs.downAction == rhs.downAction &&
               lhs.leftAction == rhs.leftAction &&
               lhs.rightAction == rhs.rightAction &&
               lhs.threshold == rhs.threshold &&
               lhs.isEnabled == rhs.isEnabled &&
               lhs.createdAt == rhs.createdAt
    }
}
