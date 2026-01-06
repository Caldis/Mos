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

// MARK: - ButtonApplicationRule
/// 按钮绑定的分应用规则 - 定义特定应用下的启用/禁用状态
struct ButtonApplicationRule: Codable, Equatable {
    
    // MARK: - 数据字段
    
    /// 唯一标识符
    let id: UUID
    
    /// 应用程序路径 (executablePath 或 bundlePath)
    let applicationPath: String
    
    /// 应用程序显示名称 (可选, 用于 UI 显示)
    var displayName: String?
    
    // MARK: - 初始化
    
    init(id: UUID = UUID(), applicationPath: String, displayName: String? = nil) {
        self.id = id
        self.applicationPath = applicationPath
        self.displayName = displayName
    }
    
    // MARK: - 工具方法
    
    /// 获取应用图标
    func getIcon() -> NSImage {
        return Utils.getApplicationIcon(fromPath: applicationPath)
    }
    
    /// 获取显示名称
    func getName() -> String {
        if let name = displayName, name.count > 0 {
            return name
        }
        return Utils.getApplicationName(fromPath: applicationPath)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ButtonApplicationRule, rhs: ButtonApplicationRule) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - ButtonBinding
/// 按钮绑定 - 将录制的事件与系统快捷键关联
struct ButtonBinding: Codable, Equatable {

    // MARK: - 数据字段

    /// 唯一标识符
    let id: UUID

    /// 录制的触发事件
    let triggerEvent: RecordedEvent

    /// 绑定的系统快捷键名称
    let systemShortcutName: String

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    let createdAt: Date
    
    /// 是否默认启用 (true = 默认对所有应用生效, false = 默认不生效)
    var isDefaultEnabled: Bool
    
    /// 禁用该绑定的应用列表 (这些应用中绑定不生效)
    var disabledApplications: [ButtonApplicationRule]
    
    /// 启用该绑定的应用列表 (这些应用中绑定生效, 即使默认关闭)
    var enabledApplications: [ButtonApplicationRule]

    // MARK: - 计算属性

    /// 获取系统快捷键对象
    var systemShortcut: SystemShortcut.Shortcut? {
        return SystemShortcut.getShortcut(named: systemShortcutName)
    }

    // MARK: - 初始化

    init(id: UUID = UUID(), triggerEvent: RecordedEvent, systemShortcutName: String, isEnabled: Bool = true, isDefaultEnabled: Bool = true, disabledApplications: [ButtonApplicationRule] = [], enabledApplications: [ButtonApplicationRule] = []) {
        self.id = id
        self.triggerEvent = triggerEvent
        self.systemShortcutName = systemShortcutName
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.isDefaultEnabled = isDefaultEnabled
        self.disabledApplications = disabledApplications
        self.enabledApplications = enabledApplications
    }
    
    // MARK: - Codable (兼容旧数据)
    
    private enum CodingKeys: String, CodingKey {
        case id, triggerEvent, systemShortcutName, isEnabled, createdAt, isDefaultEnabled, applicationRules, disabledApplications, enabledApplications
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        triggerEvent = try container.decode(RecordedEvent.self, forKey: .triggerEvent)
        systemShortcutName = try container.decode(String.self, forKey: .systemShortcutName)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // 兼容旧数据
        isDefaultEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDefaultEnabled) ?? true
        // 新格式: disabledApplications 和 enabledApplications
        disabledApplications = try container.decodeIfPresent([ButtonApplicationRule].self, forKey: .disabledApplications) ?? []
        enabledApplications = try container.decodeIfPresent([ButtonApplicationRule].self, forKey: .enabledApplications) ?? []
        // 兼容旧格式: 迁移 applicationRules 到新字段
        if let oldRules = try container.decodeIfPresent([ButtonApplicationRule].self, forKey: .applicationRules), !oldRules.isEmpty {
            if isDefaultEnabled {
                disabledApplications = oldRules
            } else {
                enabledApplications = oldRules
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(triggerEvent, forKey: .triggerEvent)
        try container.encode(systemShortcutName, forKey: .systemShortcutName)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isDefaultEnabled, forKey: .isDefaultEnabled)
        try container.encode(disabledApplications, forKey: .disabledApplications)
        try container.encode(enabledApplications, forKey: .enabledApplications)
        // 不再编码 applicationRules (已废弃)
    }

    // MARK: - Equatable

    static func == (lhs: ButtonBinding, rhs: ButtonBinding) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - 应用规则方法
    
    /// 检查指定应用是否在禁用列表中
    func isApplicationDisabled(path: String) -> Bool {
        return disabledApplications.contains { $0.applicationPath == path }
    }
    
    /// 检查指定应用是否在启用列表中
    func isApplicationEnabled(path: String) -> Bool {
        return enabledApplications.contains { $0.applicationPath == path }
    }
    
    /// 判断该绑定是否对指定应用生效
    /// - Parameter applicationPath: 应用程序路径
    /// - Returns: 是否生效
    func isActiveForApplication(_ applicationPath: String?) -> Bool {
        // 如果绑定本身未启用, 直接返回 false
        guard isEnabled else { return false }
        
        // 如果没有指定应用路径, 使用默认设置
        guard let path = applicationPath else {
            return isDefaultEnabled
        }
        
        // 检查是否在禁用列表中 (优先级最高)
        if isApplicationDisabled(path: path) {
            return false
        }
        
        // 检查是否在启用列表中
        if isApplicationEnabled(path: path) {
            return true
        }
        
        // 使用默认设置
        return isDefaultEnabled
    }
}
