//
//  RecordedEvent.swift
//  Mos
//  按钮绑定数据结构, 包含三部分
//  - EventType: 事件类型枚举 (键盘/鼠标), 供 RecordedEvent 和 ScrollHotkey 共用
//  - ScrollHotkey: 滚动热键绑定, 仅存储类型和按键码
//  - RecordedEvent: 录制后的 CGEvent 事件的完整信息, 包含修饰键和展示组件
//  - ButtonBinding: 用于存储 RecordedEvent - SystemShortcut 的绑定关系
//  Created by Claude on 2025/9/27.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

// MARK: - EventType
/// 事件类型枚举 - 键盘或鼠标
enum EventType: String, Codable {
    case keyboard = "keyboard"
    case mouse = "mouse"
}

// MARK: - ScrollHotkey
/// 滚动热键绑定 - 轻量结构，仅存储类型和按键码
/// 用于 ScrollingView 的 dash/toggle/block 热键配置
struct ScrollHotkey: Codable, Equatable {

    // MARK: - 数据字段
    let type: EventType
    let code: UInt16

    // MARK: - 初始化
    init(type: EventType, code: UInt16) {
        self.type = type
        self.code = code
    }

    init(from event: CGEvent) {
        // 键盘事件 (keyDown/keyUp) 或修饰键事件 (flagsChanged)
        if event.isKeyboardEvent || event.type == .flagsChanged {
            self.type = .keyboard
            self.code = event.keyCode
        } else {
            self.type = .mouse
            self.code = event.mouseCode
        }
    }

    /// 从旧版 Int 格式迁移 (向后兼容)
    init?(legacyCode: Int?) {
        guard let code = legacyCode else { return nil }
        self.type = .keyboard
        self.code = UInt16(code)
    }

    // MARK: - 显示名称
    var displayName: String {
        switch type {
        case .keyboard:
            return KeyCode.keyMap[code] ?? "Key \(code)"
        case .mouse:
            if LogiCenter.shared.isLogiCode(code) {
                return (LogiCenter.shared.name(forMosCode: code) ?? "")
            }
            return KeyCode.mouseMap[code] ?? "🖱\(code)"
        }
    }

    // MARK: - 事件匹配
    func matches(_ event: CGEvent, keyCode: UInt16, mouseButton: UInt16, isMouseEvent: Bool) -> Bool {
        switch type {
        case .keyboard:
            // 键盘按键或修饰键
            guard !isMouseEvent else { return false }
            return code == keyCode
        case .mouse:
            // 鼠标按键
            guard isMouseEvent else { return false }
            return code == mouseButton
        }
    }

    /// 是否为修饰键
    var isModifierKey: Bool {
        return type == .keyboard && KeyCode.modifierKeys.contains(code)
    }

    /// 获取修饰键掩码 (仅对键盘修饰键有效)
    var modifierMask: CGEventFlags {
        guard type == .keyboard else { return CGEventFlags(rawValue: 0) }
        return KeyCode.getKeyMask(code)
    }
}

// MARK: - RecordedEvent
/// 录制的事件数据 - 可序列化的事件信息 (完整版，包含修饰键)
struct RecordedEvent: Codable, Equatable {

    // MARK: - 数据字段
    let type: EventType // 事件类型
    let code: UInt16 // 按键代码
    let modifiers: UInt // 修饰键
    let displayComponents: [String] // 展示用名称组件
    let deviceFilter: DeviceFilter?

    // MARK: - 计算属性

    /// NSEvent.ModifierFlags 格式的修饰键
    var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: modifiers)
    }

    /// 转换为 ScrollHotkey (丢弃修饰键信息)
    var asScrollHotkey: ScrollHotkey {
        return ScrollHotkey(type: type, code: code)
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
        self.deviceFilter = nil
    }

    /// 从 InputEvent 构造
    init(from event: InputEvent, deviceFilter: DeviceFilter? = nil) {
        self.type = event.type
        self.code = event.code
        self.modifiers = UInt(event.modifiers.rawValue)
        self.deviceFilter = deviceFilter
        self.displayComponents = event.displayComponents
    }

    /// 便捷构造 - 直接指定所有字段
    init(type: EventType, code: UInt16, modifiers: UInt, displayComponents: [String], deviceFilter: DeviceFilter?) {
        self.type = type
        self.code = code
        self.modifiers = modifiers
        self.displayComponents = displayComponents
        self.deviceFilter = deviceFilter
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
    /// 匹配 InputEvent (供 InputProcessor 使用)
    func matchesInput(_ event: InputEvent) -> Bool {
        guard UInt(event.modifiers.rawValue) == modifiers else { return false }
        guard event.type == type else { return false }
        switch type {
        case .keyboard:
            guard code == event.code else { return false }
        case .mouse:
            guard code == event.code else { return false }
        }
        if let filter = deviceFilter {
            guard filter.matches(event.device) else { return false }
        }
        return true
    }

    /// 匹配优先级:
    /// - keyboard: 仅接受精确 modifiers 匹配
    /// - mouse: 允许额外 modifiers 存在, 返回绑定自身 modifiers 数量作为优先级
    func matchPriority(for event: InputEvent) -> Int? {
        guard event.type == type else { return nil }
        guard code == event.code else { return nil }
        if let filter = deviceFilter, !filter.matches(event.device) {
            return nil
        }

        let expectedModifiers = modifiers & UInt(KeyCode.modifiersMask)
        let actualModifiers = UInt(event.modifiers.rawValue) & UInt(KeyCode.modifiersMask)

        switch type {
        case .keyboard:
            guard actualModifiers == expectedModifiers else { return nil }
        case .mouse:
            guard actualModifiers & expectedModifiers == expectedModifiers else { return nil }
        }

        return expectedModifiers.nonzeroBitCount
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

    static let customBindingRelevantModifierMask: UInt64 =
        KeyCode.modifiersMask | CGEventFlags.maskSecondaryFn.rawValue

    /// "打开应用" 动作 sentinel; systemShortcutName 取此值时, openTarget 字段为权威载荷.
    static let openTargetSentinel = "openTarget"

    // MARK: - 持久化字段

    /// 唯一标识符
    let id: UUID

    /// 录制的触发事件
    let triggerEvent: RecordedEvent

    /// 绑定的系统快捷键名称
    /// 自定义快捷键格式: "custom::<keyCode>:<modifierFlags>"
    /// "打开应用" 动作: "openTarget" (此时 openTarget 字段非 nil)
    let systemShortcutName: String

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    let createdAt: Date

    /// "打开应用" 动作的结构化载荷; 仅当 systemShortcutName == openTargetSentinel 时非 nil.
    let openTarget: OpenTargetPayload?

    // MARK: - 瞬态缓存字段 (不参与编解码)

    /// 缓存的自定义按键码
    private(set) var cachedCustomCode: UInt16? = nil

    /// 缓存的自定义修饰键标志
    private(set) var cachedCustomModifiers: UInt64? = nil

    // MARK: - CodingKeys (仅编码持久化字段)

    enum CodingKeys: String, CodingKey {
        case id, triggerEvent, systemShortcutName, isEnabled, createdAt, openTarget
    }

    // MARK: - 计算属性

    /// 获取系统快捷键对象
    var systemShortcut: SystemShortcut.Shortcut? {
        return SystemShortcut.getShortcut(named: systemShortcutName)
    }

    /// 是否为自定义绑定
    var isCustomBinding: Bool {
        return systemShortcutName.hasPrefix("custom::")
    }

    // MARK: - 初始化

    init(id: UUID = UUID(),
         triggerEvent: RecordedEvent,
         systemShortcutName: String,
         isEnabled: Bool = true,
         createdAt: Date = Date()) {
        self.id = id
        self.triggerEvent = triggerEvent
        self.systemShortcutName = systemShortcutName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.openTarget = nil
    }

    /// "打开应用" 动作专用初始化器, 强制保证 sentinel 与 payload 一致.
    init(id: UUID = UUID(),
         triggerEvent: RecordedEvent,
         openTarget: OpenTargetPayload,
         isEnabled: Bool = true,
         createdAt: Date = Date()) {
        self.id = id
        self.triggerEvent = triggerEvent
        self.systemShortcutName = Self.openTargetSentinel
        self.openTarget = openTarget
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    // MARK: - Decode-time 一致性校验 (UI 与 executor 必须看到同一个真相)
    //
    // 不变量: systemShortcutName == openTargetSentinel ⇔ openTarget != nil
    //
    // 没有这层校验时, 手改 / AI 改写的 JSON 可能写出 mismatch 状态:
    //   - {"systemShortcutName":"copy", "openTarget":{...}}  → UI 显 "打开 Safari", 执行却跑 Copy
    //   - {"systemShortcutName":"openTarget", openTarget 缺}  → UI 显 unbound, 执行 no-op
    // decode 时 throw, 让 Options.decodeButtonBindingsWithUnknowns 把这条 binding 收到
    // preservedUnknownBindings, save 时再 round-trip 回去 (用户改 JSON 改坏了一条不会被静默吞掉).

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.triggerEvent = try c.decode(RecordedEvent.self, forKey: .triggerEvent)
        let name = try c.decode(String.self, forKey: .systemShortcutName)
        self.systemShortcutName = name
        self.isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        let payload = try c.decodeIfPresent(OpenTargetPayload.self, forKey: .openTarget)
        self.openTarget = payload

        // 强制一致性: sentinel 与 payload 同时存在或同时不存在.
        let nameIsSentinel = (name == Self.openTargetSentinel)
        let payloadIsPresent = (payload != nil)
        if nameIsSentinel != payloadIsPresent {
            throw DecodingError.dataCorruptedError(
                forKey: .openTarget,
                in: c,
                debugDescription: "Inconsistent OpenTarget binding: systemShortcutName=\"\(name)\" but openTarget \(payloadIsPresent ? "present" : "missing")"
            )
        }
    }

    // MARK: - 自定义缓存

    /// 解析 custom:: 格式并填充缓存字段
    mutating func prepareCustomCache() {
        guard let payload = Self.normalizedCustomBindingPayload(from: systemShortcutName) else {
            cachedCustomCode = nil
            cachedCustomModifiers = nil
            return
        }
        cachedCustomCode = payload.code
        cachedCustomModifiers = payload.modifiers
    }

    static func normalizedCustomBindingName(code: UInt16, modifiers: UInt64) -> String {
        let payload = normalizeCustomBindingPayload(code: code, modifiers: modifiers)
        return "custom::\(payload.code):\(payload.modifiers)"
    }

    static func normalizedCustomBindingPayload(from customBindingName: String) -> (code: UInt16, modifiers: UInt64)? {
        guard customBindingName.hasPrefix("custom::") else { return nil }
        let payload = String(customBindingName.dropFirst("custom::".count))
        let parts = payload.split(separator: ":")
        guard parts.count == 2,
              let code = UInt16(parts[0]),
              let modifiers = UInt64(parts[1]) else {
            return nil
        }
        return normalizeCustomBindingPayload(code: code, modifiers: modifiers)
    }

    static func normalizeCustomBindingPayload(code: UInt16, modifiers: UInt64) -> (code: UInt16, modifiers: UInt64) {
        var normalizedModifiers = modifiers & customBindingRelevantModifierMask
        if KeyCode.modifierKeys.contains(code) {
            normalizedModifiers &= ~KeyCode.getKeyMask(code).rawValue
        }
        return (code, normalizedModifiers)
    }

    // MARK: - Equatable (仅比较持久化字段, 忽略瞬态缓存)

    static func == (lhs: ButtonBinding, rhs: ButtonBinding) -> Bool {
        return lhs.id == rhs.id &&
               lhs.triggerEvent == rhs.triggerEvent &&
               lhs.systemShortcutName == rhs.systemShortcutName &&
               lhs.isEnabled == rhs.isEnabled &&
               lhs.createdAt == rhs.createdAt &&
               lhs.openTarget == rhs.openTarget
    }
}

// MARK: - ScrollHotkey + InputEvent
extension ScrollHotkey {
    /// 从 InputEvent 构造
    init(from event: InputEvent) {
        self.type = event.type
        self.code = event.code
    }
}
