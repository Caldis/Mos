//
//  RecordedEvent.swift
//  Mos
//  按钮绑定数据结构, 包含两部分
//  - RecordedEvent: 录制后的 CGEvent 事件的信息结构题, 可序列化存储
//  - ButtonBinding: 用于存储 RecordedEvent - SystemShortcut 的绑定关系
//  Created by Claude on 2025/9/27.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

// MARK: - RecordedEvent
/// 录制的事件数据 - 可序列化的事件信息
struct RecordedEvent: Codable, Equatable {

    // MARK: - 数据字段
    let type: EventType // 事件类型
    let code: UInt16 // 按键代码
    let modifiers: UInt // 修饰键
    let displayComponents: [String] // 展示用名称组件

    // MARK: - 枚举定义
    enum EventType: String, Codable {
        case keyboard = "keyboard"
        case mouse = "mouse"
    }

    // MARK: - 计算属性

    /// NSEvent.ModifierFlags 格式的修饰键
    var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: modifiers)
    }

    // MARK: - INIT
    init(from event: CGEvent) {
        // 修饰键
        self.modifiers = UInt(event.flags.rawValue)
        // 根据事件类型匹配
        if event.isKeyboardEvent {
            self.type = .keyboard
            self.code = event.keyCode
        } else {
            self.type = .mouse
            self.code = event.mouseCode
        }
        // 展示用名称
        self.displayComponents = event.displayComponents
    }

    // MARK: - 匹配方法
    /// 检查是否与给定的 CGEvent 匹配
    func matches(_ event: CGEvent) -> Bool {
        // Guard: 修饰键匹配
        guard event.flags.rawValue == modifiers else { return false }
        // 根据类型匹配
        switch type {
            case .keyboard:
                // Guard: 键盘事件 (这里只匹配 keyDown)
                guard event.type == .keyDown else { return false }
                // 匹配 code
                return code == Int(event.getIntegerValueField(.keyboardEventKeycode))
            case .mouse:
                // Guard: 鼠标事件
                guard event.type != .keyDown && event.type != .keyUp else { return false }
                // 匹配 code
                return code == Int(event.getIntegerValueField(.mouseEventButtonNumber))
        }
    }
    /// Equatable
    static func == (lhs: RecordedEvent, rhs: RecordedEvent) -> Bool {
        return lhs.type == rhs.type &&
               lhs.code == rhs.code &&
               lhs.modifiers == rhs.modifiers
    }
}

// MARK: - ButtonBinding
/// 按钮绑定 - 将录制的事件与系统快捷键关联
struct ButtonBinding: Codable, Equatable {

    // MARK: - 数据字段

    /// 录制的触发事件
    let triggerEvent: RecordedEvent

    /// 绑定的系统快捷键名称
    let systemShortcutName: String

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    let createdAt: Date

    // MARK: - 计算属性

    /// 获取系统快捷键对象
    var systemShortcut: SystemShortcut.Shortcut? {
        return SystemShortcut.getShortcut(named: systemShortcutName)
    }

    // MARK: - 初始化

    init(triggerEvent: RecordedEvent, systemShortcutName: String, isEnabled: Bool = true) {
        self.triggerEvent = triggerEvent
        self.systemShortcutName = systemShortcutName
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }

    // MARK: - Equatable

    static func == (lhs: ButtonBinding, rhs: ButtonBinding) -> Bool {
        return lhs.triggerEvent == rhs.triggerEvent &&
               lhs.systemShortcutName == rhs.systemShortcutName
    }
}
