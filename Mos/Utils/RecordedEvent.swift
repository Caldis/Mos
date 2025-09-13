//
//  RecordedEvent.swift
//  Mos
//  录制的事件数据结构
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

// MARK: - 组合键数据结构
struct RecordedEvent {
    var modifierFlags: NSEvent.ModifierFlags
    var mouseButton: Int?
    var keyCode: UInt16?

    var hasModifiers: Bool {
        return !modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty
    }

    var isValid: Bool {
        // 修饰键不能单独存在，必须和鼠标或键盘按键组合
        if mouseButton == nil && keyCode == nil {
            return false
        }
        // 纯修饰键不允许被记录
        if keyCode != nil && isModifierKey(keyCode!) && mouseButton == nil {
            return false
        }
        return true
    }

    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        return KeyCodeConstants.modifierKeys.contains(keyCode)
    }

    func displayName() -> String {
        var components: [String] = []

        // 使用扩展方法格式化修饰键
        let modifierString = modifierFlags.formattedString(excludeFnForFunctionKeys: keyCode)
        if !modifierString.isEmpty {
            components.append(modifierString)
        }

        // 添加主键
        if let mouseButton = mouseButton {
            switch mouseButton {
            case 0: components.append("🖱L") // 左键
            case 1: components.append("🖱R") // 右键
            case 2: components.append("🖱M") // 中键
            default: components.append("🖱\(mouseButton + 1)") // 其他鼠标按键
            }
        }

        if let keyCode = keyCode {
            components.append(keyCodeToString(keyCode))
        }

        return components.joined(separator: " + ")
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        return KeyCodeConstants.keyMap[keyCode] ?? "Key(\(keyCode))"
    }
}