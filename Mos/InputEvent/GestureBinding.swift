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

/// 手势绑定 - 将录制的触发按键与动作关联
/// Movement (鼠标移动): 4 方向 (↑↓←→), 阈值默认 30px
/// Scroll   (滚轮滚动): 2 方向 (↑↓),   阈值默认 3 tick
/// 两种输入模式相互独立, 可同时配置
struct GestureBinding: Codable, Equatable {

    // MARK: - 持久化字段

    let id: UUID
    let triggerEvent: RecordedEvent
    let createdAt: Date

    // --- Movement 动作 (鼠标移动方向, 4 方向) ---
    var upAction:    String?
    var downAction:  String?
    var leftAction:  String?
    var rightAction: String?
    /// 触发方向识别所需最小移动像素
    var threshold: Double

    // --- Scroll 动作 (滚轮方向, 仅 ↑↓) ---
    var scrollUpAction:   String?
    var scrollDownAction: String?
    /// 触发方向识别所需最小滚轮 tick 数
    var scrollThreshold: Double

    var isEnabled: Bool

    // MARK: - 初始化

    init(
        id: UUID = UUID(),
        triggerEvent: RecordedEvent,
        upAction: String? = nil,
        downAction: String? = nil,
        leftAction: String? = nil,
        rightAction: String? = nil,
        threshold: Double = 30.0,
        scrollUpAction: String? = nil,
        scrollDownAction: String? = nil,
        scrollThreshold: Double = 3.0,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id              = id
        self.triggerEvent    = triggerEvent
        self.upAction        = upAction
        self.downAction      = downAction
        self.leftAction      = leftAction
        self.rightAction     = rightAction
        self.threshold       = threshold
        self.scrollUpAction  = scrollUpAction
        self.scrollDownAction = scrollDownAction
        self.scrollThreshold = scrollThreshold
        self.isEnabled       = isEnabled
        self.createdAt       = createdAt
    }

    // MARK: - Codable (backward-compatible)

    enum CodingKeys: String, CodingKey {
        case id, triggerEvent, createdAt
        case upAction, downAction, leftAction, rightAction, threshold
        case scrollUpAction, scrollDownAction, scrollThreshold
        case isEnabled
        // Legacy key — present in old data, decoded and discarded
        case inputMode
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(triggerEvent,    forKey: .triggerEvent)
        try c.encode(createdAt,       forKey: .createdAt)
        try c.encodeIfPresent(upAction,        forKey: .upAction)
        try c.encodeIfPresent(downAction,      forKey: .downAction)
        try c.encodeIfPresent(leftAction,      forKey: .leftAction)
        try c.encodeIfPresent(rightAction,     forKey: .rightAction)
        try c.encode(threshold,                forKey: .threshold)
        try c.encodeIfPresent(scrollUpAction,  forKey: .scrollUpAction)
        try c.encodeIfPresent(scrollDownAction, forKey: .scrollDownAction)
        try c.encode(scrollThreshold,          forKey: .scrollThreshold)
        try c.encode(isEnabled,                forKey: .isEnabled)
        // inputMode intentionally NOT encoded (legacy read-only key)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,         forKey: .id)
        triggerEvent = try c.decode(RecordedEvent.self, forKey: .triggerEvent)
        createdAt    = try c.decode(Date.self,         forKey: .createdAt)

        upAction    = try c.decodeIfPresent(String.self, forKey: .upAction)
        downAction  = try c.decodeIfPresent(String.self, forKey: .downAction)
        leftAction  = try c.decodeIfPresent(String.self, forKey: .leftAction)
        rightAction = try c.decodeIfPresent(String.self, forKey: .rightAction)

        // Legacy: threshold was the single threshold field (used for both modes).
        // Map it to movement threshold; default 30.0 if absent.
        threshold = (try? c.decodeIfPresent(Double.self, forKey: .threshold)) ?? 30.0

        scrollUpAction   = try c.decodeIfPresent(String.self, forKey: .scrollUpAction)
        scrollDownAction = try c.decodeIfPresent(String.self, forKey: .scrollDownAction)
        scrollThreshold  = (try? c.decodeIfPresent(Double.self, forKey: .scrollThreshold)) ?? 3.0

        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)

        // inputMode key is silently ignored (no longer used)
    }

    // MARK: - 方向动作访问 (Movement)

    /// 获取指定 Movement 方向的动作名称
    func action(for direction: GestureDirection) -> String? {
        switch direction {
        case .up:    return upAction
        case .down:  return downAction
        case .left:  return leftAction
        case .right: return rightAction
        }
    }

    /// 设置指定 Movement 方向的动作 (返回更新后的副本)
    func withAction(_ action: String?, for direction: GestureDirection) -> GestureBinding {
        var copy = self
        switch direction {
        case .up:    copy.upAction    = action
        case .down:  copy.downAction  = action
        case .left:  copy.leftAction  = action
        case .right: copy.rightAction = action
        }
        return copy
    }

    // MARK: - 方向动作访问 (Scroll)

    /// 获取指定 Scroll 方向的动作名称 (仅 .up / .down 有效)
    func scrollAction(for direction: GestureDirection) -> String? {
        switch direction {
        case .up:   return scrollUpAction
        case .down: return scrollDownAction
        default:    return nil
        }
    }

    /// 设置指定 Scroll 方向的动作 (返回更新后的副本)
    func withScrollAction(_ action: String?, for direction: GestureDirection) -> GestureBinding {
        var copy = self
        switch direction {
        case .up:   copy.scrollUpAction   = action
        case .down: copy.scrollDownAction = action
        default: break
        }
        return copy
    }

    // MARK: - 能力查询

    var hasAnyMovementAction: Bool {
        return upAction != nil || downAction != nil || leftAction != nil || rightAction != nil
    }

    var hasAnyScrollAction: Bool {
        return scrollUpAction != nil || scrollDownAction != nil
    }

    var hasAnyAction: Bool {
        return hasAnyMovementAction || hasAnyScrollAction
    }

    // MARK: - Equatable

    static func == (lhs: GestureBinding, rhs: GestureBinding) -> Bool {
        return lhs.id              == rhs.id              &&
               lhs.triggerEvent   == rhs.triggerEvent     &&
               lhs.upAction       == rhs.upAction         &&
               lhs.downAction     == rhs.downAction       &&
               lhs.leftAction     == rhs.leftAction       &&
               lhs.rightAction    == rhs.rightAction      &&
               lhs.threshold      == rhs.threshold        &&
               lhs.scrollUpAction   == rhs.scrollUpAction   &&
               lhs.scrollDownAction == rhs.scrollDownAction &&
               lhs.scrollThreshold  == rhs.scrollThreshold  &&
               lhs.isEnabled      == rhs.isEnabled        &&
               lhs.createdAt      == rhs.createdAt
    }
}
