//
//  GestureBinding.swift
//  Mos
//  鼠标手势绑定数据结构
//  Created by Claude on 2026/4/15.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - GestureInputMode

/// 手势输入模式: 鼠标移动 或 滚轮滚动
enum GestureInputMode: String, Codable, CaseIterable {
    case mouseMovement = "mouseMovement"  // 移动鼠标触发方向 (默认)
    case scrollWheel   = "scrollWheel"   // 滚轮滚动触发方向
}

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

    /// 移动阈值, 超过后触发方向识别
    /// mouseMovement 模式: 像素距离 (默认 30.0)
    /// scrollWheel 模式: 滚轮行数 (默认 3.0)
    var threshold: Double

    /// 手势输入模式 (默认 mouseMovement, 向后兼容)
    var inputMode: GestureInputMode

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
        inputMode: GestureInputMode = .mouseMovement,
        threshold: Double? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.triggerEvent = triggerEvent
        self.upAction = upAction
        self.downAction = downAction
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.inputMode = inputMode
        // Default threshold depends on input mode
        self.threshold = threshold ?? (inputMode == .scrollWheel ? 3.0 : 30.0)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    // MARK: - Codable (backward-compatible)

    enum CodingKeys: String, CodingKey {
        case id, triggerEvent, upAction, downAction, leftAction, rightAction
        case threshold, inputMode, isEnabled, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,          forKey: .id)
        triggerEvent = try c.decode(RecordedEvent.self,  forKey: .triggerEvent)
        upAction     = try c.decodeIfPresent(String.self, forKey: .upAction)
        downAction   = try c.decodeIfPresent(String.self, forKey: .downAction)
        leftAction   = try c.decodeIfPresent(String.self, forKey: .leftAction)
        rightAction  = try c.decodeIfPresent(String.self, forKey: .rightAction)
        // inputMode defaults to .mouseMovement for bindings saved before this field existed
        inputMode    = (try? c.decodeIfPresent(GestureInputMode.self, forKey: .inputMode)) ?? .mouseMovement
        threshold    = try c.decode(Double.self,        forKey: .threshold)
        isEnabled    = try c.decode(Bool.self,          forKey: .isEnabled)
        createdAt    = try c.decode(Date.self,          forKey: .createdAt)
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

    /// 设置输入模式 (返回更新后的副本, 并重置阈值为模式默认值)
    func withInputMode(_ mode: GestureInputMode) -> GestureBinding {
        var copy = self
        copy.inputMode = mode
        copy.threshold = (mode == .scrollWheel) ? 3.0 : 30.0
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
               lhs.inputMode == rhs.inputMode &&
               lhs.isEnabled == rhs.isEnabled &&
               lhs.createdAt == rhs.createdAt
    }
}
