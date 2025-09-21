//
//  CGEvent+Extensions.swift
//  Mos
//  CGEvent 相关的扩展方法
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

extension CGEvent {
    /// 格式化修饰键为显示字符串
    func formattedString(excludeFnForFunctionKeys keyCode: UInt16? = nil) -> String {
        var components: [String] = []

        // SHIFT
        if flags.contains(.maskShift) { components.append("⇧") }
        // FN
        if flags.contains(.maskSecondaryFn) {
            // 如果是Fn+F键组合，隐去Fn避免误导
            if let keyCode = keyCode, isFunctionKey(keyCode) {
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

    /// 检查是否为F键
    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        return KeyCode.functionKeys.contains(keyCode)
    }
}

