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
        return formatModifierString(from: keyCode)
    }

    /// 键码
    var keyCode: UInt16 {
        return UInt16(getIntegerValueField(.keyboardEventKeycode))
    }

    /// 鼠标按键编号
    var mouseButton: Int? {
        return Int(getIntegerValueField(.mouseEventButtonNumber))
    }

    /// NSEvent 修饰键标志
    var nsEventFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
    }

    /// 是否有修饰键
    var hasModifiers: Bool {
        return !nsEventFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty
    }

    /// 是否为鼠标事件
    var isMouseEvent: Bool {
        switch CGEventType(rawValue: UInt32(type.rawValue)) {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    /// 事件是否有效
    var isValid: Bool {
        // 纯修饰键不允许被记录
        if KeyCode.modifierKeys.contains(keyCode) && mouseButton == nil {
            return false
        }
        return true
    }


    // MARK: - Utils

    /// 显示名称
    public func displayName() -> String {
        var components: [String] = []

        // 使用扩展方法格式化修饰键
        if !modifierString.isEmpty {
            components.append(modifierString)
        }

        // 根据事件类型判断需要展示的内容, 鼠标和键盘事件(非修饰键)互斥
        if isMouseEvent, let mouseButton = mouseButton {
            // 鼠标事件
            switch mouseButton {
                case 0: components.append("🖱L") // 左键
                case 1: components.append("🖱R") // 右键
                case 2: components.append("🖱M") // 中键
                default: components.append("🖱\(mouseButton + 1)") // 其他鼠标按键
            }
        } else {
            // 键盘事件或其他事件，添加按键名称
            components.append(getKeyString(from: keyCode))
        }

        return components.joined(separator: " + ")
    }

    /// 格式化修饰键为显示字符串
    private func formatModifierString(from keyCode: UInt16? = nil) -> String {
        var components: [String] = []

        // SHIFT
        if flags.contains(.maskShift) { components.append("⇧") }
        // FN
        if flags.contains(.maskSecondaryFn) {
            // 如果是Fn+F键或方向键组合，隐去Fn避免误导
            if let keyCode = keyCode, (isFunctionKey(keyCode) || isArrowKey(keyCode)) {
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

        return components.joined(separator: " ")
    }

    /// 键码转字符串
    private func getKeyString(from keyCode: UInt16) -> String {
        return KeyCode.keyMap[keyCode] ?? "Key(\(keyCode))"
    }

    /// 检查是否为 FN 键
    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        return KeyCode.functionKeys.contains(keyCode)
    }

    private func isArrowKey(_ keyCode: UInt16) -> Bool {
        return KeyCode.arrowKeys.contains(keyCode)
    }
}

