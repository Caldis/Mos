//
//  CGEvent+Extensions.swift
//  Mos
//  CGEvent 相关的扩展方法
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

extension CGEvent {

    // MARK: - Properties

    /// 格式化修饰键字符串
    var modifierString: String {
        var components: [String] = []
        // SHIFT
        if flags.contains(.maskShift) { components.append("⇧") }
        // FN
        if flags.contains(.maskSecondaryFn) {
            // 如果是Fn+F键或方向键组合，隐去Fn避免误导
            if isFunctionKey || isArrowKey {
                // Fn+F键组合不显示Fn
            } else {
                components.append("Fn")
            }
        }
        // CTRL
        if flags.contains(.maskControl) { components.append("⌃") }
        // OPTION
        if flags.contains(.maskAlternate) { components.append("⌥") }
        // COMMAND
        if flags.contains(.maskCommand) { components.append("⌘") }
        // 使用空格拼接
        return components.joined(separator: " ")
    }

    /// 键盘键码 (如果没值就是0)
    var keyCode: UInt16 {
        return UInt16(getIntegerValueField(.keyboardEventKeycode))
    }

    /// 键盘键码名称
    var keyCodeName: String {
        return KeyCode.keyMap[keyCode] ?? "Key(\(keyCode))"
    }

    /// 鼠标键码 (如果没值就是0, 会和鼠标主键冲突, 因此取值之前需要先判断 isMouseEvent)
    var mouseCode: UInt16 {
        return UInt16(getIntegerValueField(.mouseEventButtonNumber))
    }

    var mouseCodeName: String {
        return KeyCode.mouseMap[keyCode] ?? "Mouse(\(keyCode))"
    }

    /// NSEvent 修饰键标志
    var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
    }

    /// 是否有修饰键
    var hasModifiers: Bool {
        return !modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty
    }

    /// 是否为 F* 键
    var isFunctionKey: Bool {
        return KeyCode.functionKeys.contains(keyCode)
    }

    /// 是否为方向键
    var isArrowKey: Bool {
        return KeyCode.arrowKeys.contains(keyCode)
    }

    /// 是否为键盘事件
    var isKeyboardEvent: Bool {
        switch type {
            case .keyDown, .keyUp:
                return true
            default:
                return false
        }
    }

    /// 是否为鼠标事件
    var isMouseEvent: Bool {
        switch type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                return true
            default:
                return false
        }
    }

    /// 事件是否有效
    var isRecordable: Bool {
        // 无修饰键不允许被记录
        if !hasModifiers {
            return false
        }
        // 纯修饰键不允许被记录
        if hasModifiers && isKeyboardEvent && keyCode == 0 {
            return false
        }
        return true
    }

    /// 时间戳
    var timestampFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date(timeIntervalSince1970: (Double(self.timestamp)) / 1_000_000_000.0))
    }

    /// 显示名称 (原始分组)
    var displayComponents: [String] {
        var components: [String] = []
        // 修饰键
        if !modifierString.isEmpty {
            components.append(modifierString)
        }
        // 键盘
        if isKeyboardEvent {
            components.append(keyCodeName)
        }
        // 鼠标
        if isMouseEvent {
            components.append(mouseCodeName)
        }
        return components
    }

    /// 显示名称
    var displayName: String {
        return displayComponents.joined(separator: " + ") // 使用 "+" 拼接
    }

}

