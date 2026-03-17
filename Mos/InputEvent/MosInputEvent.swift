//
//  MosInputEvent.swift
//  Mos
//  统一输入事件 - 抽象 CGEventTap 和 HID++ 两种事件源
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - MosInputPhase
/// 事件阶段
enum MosInputPhase {
    case down
    case up
}

// MARK: - MosInputSource
/// 事件来源 - 携带源头特有的数据
/// 注意: 因为 cgEvent 关联值包含 CGEvent (非 Codable), MosInputEvent 整体不可序列化
/// 只有从中提取的 RecordedEvent 走持久化路径
enum MosInputSource {
    /// 来自 CGEventTap, 携带原始 CGEvent 用于 pass-through/consume
    case cgEvent(CGEvent)
    /// 来自 Logitech HID++ 协议
    case hidPlusPlus
}

// MARK: - MosInputDevice
/// 设备信息 (可序列化, 用于 DeviceFilter 匹配和 UI 展示)
struct MosInputDevice: Codable, Equatable {
    let vendorId: UInt16      // USB Vendor ID (Logitech = 0x046D)
    let productId: UInt16     // USB Product ID
    let name: String          // 人类可读名称 (如 "MX Master 3S")
}

// MARK: - DeviceFilter
/// 设备过滤器 - 用于 ButtonBinding 中限制触发设备
struct DeviceFilter: Codable, Equatable {
    let vendorId: UInt16?     // nil = 不限厂商
    let productId: UInt16?    // nil = 不限型号

    func matches(_ device: MosInputDevice?) -> Bool {
        guard let device = device else { return false }
        if let vid = vendorId, vid != device.vendorId { return false }
        if let pid = productId, pid != device.productId { return false }
        return true
    }
}

// MARK: - LogitechCIDMap
/// Logitech CID -> Mos 按钮码映射
/// 标准 CGEvent 鼠标按钮: 0~31, Logitech HID++ 专有: 1000+
struct LogitechCIDMap {
    private static let cidToCode: [UInt16: UInt16] = [
        0x0050: 1003,  // Left Click (diverted)
        0x0051: 1004,  // Right Click (diverted)
        0x0052: 1005,  // Middle Click (diverted)
        0x0053: 1006,  // Back (diverted)
        0x0056: 1007,  // Forward (diverted)
        0x00C3: 1000,  // Gesture Button
        0x00C4: 1001,  // SmartShift
        0x00D7: 1002,  // DPI Change Button
    ]

    static func toMosCode(_ cid: UInt16) -> UInt16 {
        if let known = cidToCode[cid] { return known }
        let mapped = UInt32(2000) + UInt32(cid)
        return mapped <= UInt32(UInt16.max) ? UInt16(mapped) : UInt16(cid & 0x0FFF) + 2000
    }

    static func displayName(forCode code: UInt16) -> String {
        switch code {
        case 1000: return "Gesture"
        case 1001: return "SmartShift"
        case 1002: return "DPI"
        case 1003: return "Left Click"
        case 1004: return "Right Click"
        case 1005: return "Middle Click"
        case 1006: return "Back"
        case 1007: return "Forward"
        default:   return "Logi(\(code))"
        }
    }

    /// 判断按钮码是否属于 Logitech HID++ 专有范围
    static func isLogitechCode(_ code: UInt16) -> Bool {
        return code >= 1000
    }

    /// 反向映射: Mos code → CID
    static func toCID(_ mosCode: UInt16) -> UInt16? {
        if let entry = cidToCode.first(where: { $0.value == mosCode }) {
            return entry.key
        }
        // 反向 fallback (2000 + cid)
        if mosCode >= 2000 {
            return mosCode - 2000
        }
        return nil
    }
}

// MARK: - MosInputEvent
/// 统一输入事件 (运行时对象, 不可序列化)
struct MosInputEvent {
    let type: EventType           // .keyboard 或 .mouse (复用现有枚举)
    let code: UInt16              // 按键码 / 按钮码
    let modifiers: CGEventFlags   // 修饰键状态
    let phase: MosInputPhase      // 按下 / 抬起
    let source: MosInputSource    // 事件来源
    let device: MosInputDevice?   // 设备信息 (CGEventTap 来源为 nil)

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
         phase: MosInputPhase, source: MosInputSource, device: MosInputDevice?) {
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
        var components: [String] = []
        // 修饰键
        if modifiers.rawValue & CGEventFlags.maskShift.rawValue != 0 { components.append("⇧") }
        if modifiers.rawValue & CGEventFlags.maskControl.rawValue != 0 { components.append("⌃") }
        if modifiers.rawValue & CGEventFlags.maskAlternate.rawValue != 0 { components.append("⌥") }
        if modifiers.rawValue & CGEventFlags.maskCommand.rawValue != 0 { components.append("⌘") }
        // 按键名称
        switch type {
        case .keyboard:
            components.append(KeyCode.keyMap[code] ?? "Key(\(code))")
        case .mouse:
            if LogitechCIDMap.isLogitechCode(code) {
                components.append(LogitechCIDMap.displayName(forCode: code))
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
            if LogitechCIDMap.isLogitechCode(code) { return true }
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
}
