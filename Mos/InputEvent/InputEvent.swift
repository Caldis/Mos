//
//  InputEvent.swift
//  Mos
//  统一输入事件 - 抽象 CGEventTap 和 HID++ 两种事件源
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - InputPhase
/// 事件阶段
enum InputPhase {
    case down
    case up
}

// MARK: - InputSource
/// 事件来源 - 携带源头特有的数据
/// 注意: 因为 cgEvent 关联值包含 CGEvent (非 Codable), InputEvent 整体不可序列化
/// 只有从中提取的 RecordedEvent 走持久化路径
enum InputSource {
    /// 来自 CGEventTap, 携带原始 CGEvent 用于 pass-through/consume
    case cgEvent(CGEvent)
    /// 来自 Logitech HID++ 协议
    case hidPP
}

// MARK: - InputDevice
/// 设备信息 (可序列化, 用于 DeviceFilter 匹配和 UI 展示)
struct InputDevice: Codable, Equatable {
    let vendorId: UInt16      // USB Vendor ID (Logitech = 0x046D)
    let productId: UInt16     // USB Product ID
    let name: String          // 人类可读名称 (如 "MX Master 3S")
}

// MARK: - DeviceFilter
/// 设备过滤器 - 用于 ButtonBinding 中限制触发设备
struct DeviceFilter: Codable, Equatable {
    let vendorId: UInt16?     // nil = 不限厂商
    let productId: UInt16?    // nil = 不限型号

    func matches(_ device: InputDevice?) -> Bool {
        guard let device = device else { return false }
        if let vid = vendorId, vid != device.vendorId { return false }
        if let pid = productId, pid != device.productId { return false }
        return true
    }
}

// MARK: - InputEvent
/// 统一输入事件 (运行时对象, 不可序列化)
struct InputEvent {
    let type: EventType           // .keyboard 或 .mouse (复用现有枚举)
    let code: UInt16              // 按键码 / 按钮码
    let modifiers: CGEventFlags   // 修饰键状态
    let phase: InputPhase      // 按下 / 抬起
    let source: InputSource    // 事件来源
    let device: InputDevice?   // 设备信息 (CGEventTap 来源为 nil)

    /// 从 CGEvent 构造
    /// 注意: .flagsChanged 事件也属于键盘域 (修饰键按下/抬起), 必须和 keyDown/keyUp 同类处理
    /// 这与 ScrollHotkey.init(from: CGEvent) 和 RecordedEvent.init(from: CGEvent) 中的判断一致
    init(fromCGEvent event: CGEvent) {
        if event.isKeyboardEvent || event.type == .flagsChanged {
            self.type = .keyboard
            self.code = event.keyCode
        } else {
            self.type = .mouse
            self.code = event.mouseCode
        }
        self.modifiers = event.flags
        self.phase = event.isKeyDown ? .down : .up
        self.source = .cgEvent(event)
        self.device = nil
    }

    /// 从 HID++ 数据构造
    init(type: EventType, code: UInt16, modifiers: CGEventFlags,
         phase: InputPhase, source: InputSource, device: InputDevice?) {
        self.type = type
        self.code = code
        self.modifiers = modifiers
        self.phase = phase
        self.source = source
        self.device = device
    }

    // MARK: - Display

    /// 构造展示用名称组件
    var displayComponents: [String] {
        // 纯修饰键组合: 合并所有 flags 后按固定顺序构建单字符串,
        // 与录制过程中 modifierString 的顺序一致 (⇧ Fn ⌃ ⌥ ⌘), 避免视觉跳跃
        if type == .keyboard && KeyCode.modifierKeys.contains(code) {
            let allFlags = modifiers.rawValue | KeyCode.getKeyMask(code).rawValue
            var symbols: [String] = []
            if allFlags & CGEventFlags.maskShift.rawValue != 0 { symbols.append("⇧") }
            if allFlags & CGEventFlags.maskSecondaryFn.rawValue != 0 { symbols.append("Fn") }
            if allFlags & CGEventFlags.maskControl.rawValue != 0 { symbols.append("⌃") }
            if allFlags & CGEventFlags.maskAlternate.rawValue != 0 { symbols.append("⌥") }
            if allFlags & CGEventFlags.maskCommand.rawValue != 0 { symbols.append("⌘") }
            return [symbols.joined(separator: " ")]
        }

        // 非纯修饰键: 修饰键合并为单个 badge + 按键 badge
        // 与录制时 [⌃ ⌥ ⌘]+[?] 的格式一致
        var modSymbols: [String] = []
        let selfMask = KeyCode.getKeyMask(code).rawValue
        if modifiers.rawValue & CGEventFlags.maskShift.rawValue != 0 && CGEventFlags.maskShift.rawValue & selfMask == 0 { modSymbols.append("⇧") }
        if modifiers.rawValue & CGEventFlags.maskSecondaryFn.rawValue != 0 && CGEventFlags.maskSecondaryFn.rawValue & selfMask == 0 { modSymbols.append("Fn") }
        if modifiers.rawValue & CGEventFlags.maskControl.rawValue != 0 && CGEventFlags.maskControl.rawValue & selfMask == 0 { modSymbols.append("⌃") }
        if modifiers.rawValue & CGEventFlags.maskAlternate.rawValue != 0 && CGEventFlags.maskAlternate.rawValue & selfMask == 0 { modSymbols.append("⌥") }
        if modifiers.rawValue & CGEventFlags.maskCommand.rawValue != 0 && CGEventFlags.maskCommand.rawValue & selfMask == 0 { modSymbols.append("⌘") }
        var components: [String] = []
        if !modSymbols.isEmpty {
            components.append(modSymbols.joined(separator: " "))
        }
        switch type {
        case .keyboard:
            components.append(KeyCode.keyMap[code] ?? "Key(\(code))")
        case .mouse:
            if LogiCenter.shared.isLogiCode(code) {
                components.append((LogiCenter.shared.name(forMosCode: code) ?? ""))
                components.append("[Logi]")  // 特殊标记, KeyPreview 渲染为 tag
            } else {
                components.append(KeyCode.mouseMap[code] ?? "Mouse(\(code))")
            }
        }
        return components
    }

    /// 是否为键盘事件
    var isKeyboardEvent: Bool { type == .keyboard }

    /// 是否为鼠标事件
    var isMouseEvent: Bool { type == .mouse }

    /// 是否有修饰键
    var hasModifiers: Bool {
        return modifiers.rawValue & KeyCode.modifiersMask != 0
    }

    /// 事件是否可录制 (combination 模式)
    var isRecordable: Bool {
        switch type {
        case .keyboard:
            if KeyCode.functionKeys.contains(code) { return true }
            if !hasModifiers { return false }
            return true
        case .mouse:
            if LogiCenter.shared.isLogiCode(code) { return true }
            if KeyCode.mouseMainKeys.contains(code) { return hasModifiers }
            return true
        }
    }

    /// 事件是否可录制 (singleKey 模式)
    /// 注意: 修饰键 (.flagsChanged) 只在 key-down 时录制, key-up 忽略
    /// 这与原 KeyRecorder.isRecordableAsSingleKey 中 event.isKeyDown && event.isModifiers 逻辑一致
    var isRecordableAsSingleKey: Bool {
        switch type {
        case .keyboard:
            if KeyCode.modifierKeys.contains(code) {
                return phase == .down
            }
            return true
        case .mouse:
            if KeyCode.mouseMainKeys.contains(code) { return false }
            return true
        }
    }

    /// 事件是否可录制 (adaptive 模式 — 接受所有可用输入)
    var isRecordableAsAdaptive: Bool {
        switch type {
        case .keyboard:
            // 修饰键: 只在 down 时录制
            if KeyCode.modifierKeys.contains(code) {
                return phase == .down
            }
            return true
        case .mouse:
            if code == 0 { return false }
            return true
        }
    }
}
