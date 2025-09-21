//
//  KeyEvent.swift
//  Mos
//  录制的事件数据结构
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

// MARK: - 组合键数据结构
struct KeyEvent {
    var event: CGEvent

    var modifierString: String {
        return event.formattedString(excludeFnForFunctionKeys: keyCode)
    }
    var keyCode: UInt16 {
        return UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    }
    var mouseButton: Int? {
        return Int(event.getIntegerValueField(.mouseEventButtonNumber))
    }
    var flags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
    }
    var hasModifiers: Bool {
        return !flags.intersection([.command, .option, .control, .shift, .function]).isEmpty
    }
    var isMouseEvent: Bool {
        switch CGEventType(rawValue: UInt32(event.type.rawValue)) {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    var isValid: Bool {
        // 纯修饰键不允许被记录
        if KeyCode.modifierKeys.contains(keyCode) && mouseButton == nil {
            return false
        }
        return true
    }

    func displayName() -> String {
        var components: [String] = []

        // 使用扩展方法格式化修饰键
        if !modifierString.isEmpty {
            components.append(modifierString)
        }

        // 根据事件类型判断需要展示的内容
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
            components.append(keyCodeToString(keyCode))
        }

        return components.joined(separator: " + ")
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        return KeyCode.keyMap[keyCode] ?? "Key(\(keyCode))"
    }
}
