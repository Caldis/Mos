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

    /// 修饰键
    var isModifiers: Bool {
        KeyCode.modifierKeys.contains(keyCode)
    }
    var hasModifiers: Bool {
        return flags.rawValue & KeyCode.modifiersMask != 0
    }

    /// 是否按下
    var isKeyDown: Bool {
        // 修饰键, 则比对按键是否匹配 mask
        if type == CGEventType.flagsChanged {
            return flags.contains(KeyCode.getKeyMask(keyCode))
        }
        // 常规情况
        return type == CGEventType.keyDown
    }
    var isKeyUp: Bool {
        return !isKeyDown
    }

    /// Command 键
    var isCommandKey: Bool {
        return KeyCode.commandKeys.contains(keyCode)
    }
    var hasCommandKey: Bool {
        return flags.rawValue & CGEventFlags.maskCommand.rawValue  != 0
    }

    /// Option 键
    var isOptionKey: Bool {
        return KeyCode.optionKeys.contains(keyCode)
    }
    var hasOptionKey: Bool {
        return flags.rawValue & CGEventFlags.maskAlternate.rawValue  != 0
    }

    /// Control 键
    var isControlKey: Bool {
        return KeyCode.controlKeys.contains(keyCode)
    }
    var hasControlKey: Bool {
        return flags.rawValue & CGEventFlags.maskControl.rawValue  != 0
    }

    /// Shift 键
    var isShiftKey: Bool {
        return KeyCode.shiftKeys.contains(keyCode)
    }
    var hasShiftKey: Bool {
        return flags.rawValue & CGEventFlags.maskShift.rawValue  != 0
    }

    /// fn 键
    var isFnKey: Bool {
        return KeyCode.fnKeys.contains(keyCode)
    }
    var hasFnKey: Bool {
        return flags.rawValue & CGEventFlags.maskSecondaryFn.rawValue  != 0
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
        // 键盘事件
        if isKeyboardEvent {
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
        // 鼠标事件
        if isMouseEvent {
            // 如果是左中右则必须包含修饰键
            if !hasModifiers && KeyCode.mouseMainKeys.contains(mouseCode) {
                return false
            }
            return true
        }
        // 其他不做处理
        return false
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

