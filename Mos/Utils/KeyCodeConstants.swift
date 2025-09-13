//
//  KeyCodeConstants.swift
//  Mos
//  键盘和事件相关的常量定义
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

// MARK: - 键盘常量
struct KeyCodeConstants {
    // 特殊功能键
    static let escape: UInt16 = 53
    static let space: UInt16 = 49
    static let backspace: UInt16 = 51
    static let enter: UInt16 = 76
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let grave: UInt16 = 50 // `键

    // 修饰键
    static let leftCommand: UInt16 = 55
    static let rightCommand: UInt16 = 54
    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let leftOption: UInt16 = 58
    static let rightOption: UInt16 = 61
    static let leftControl: UInt16 = 59
    static let rightControl: UInt16 = 62
    static let function: UInt16 = 179

    static let modifierKeys: Set<UInt16> = [54, 55, 58, 59, 60, 61, 62, 179]

    // F键系列
    static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 111, 103, 109, 105, 107, 113]

    // 完整键盘映射
    static let keyMap: [UInt16: String] = [
        // 字母键
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        // 数字键
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 26: "7", 28: "8", 29: "0", 25: "9",
        // 符号键
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        // 特殊键
        49: "⎵", 51: "⌫", 53: "⎋", 76: "↩", 36: "↩", 48: "↹", 179: "Fn",
        // F键 (兼容 MacBook 功能键)
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 111: "F10", 103: "F11", 109: "F12", 105: "F13", 107: "F14", 113: "F15"
    ]
}

// MARK: - 事件录制常量
struct EventRecorderConstants {
    // 通知名称
    static let recordNotificationName = NSNotification.Name("EventRecorded")
    static let modifierFlagsChangedNotificationName = NSNotification.Name("ModifierFlagsChanged")
    static let recordingCancelledNotificationName = NSNotification.Name("RecordingCancelled")

    // 超时时间
    static let recordTimeout: TimeInterval = 10.0

    // 键盘常量的别名，保持向后兼容
    struct KeyCode {
        // 特殊功能键
        static let escape = KeyCodeConstants.escape
        static let space = KeyCodeConstants.space
        static let backspace = KeyCodeConstants.backspace
        static let enter = KeyCodeConstants.enter
        static let returnKey = KeyCodeConstants.returnKey
        static let tab = KeyCodeConstants.tab
        static let grave = KeyCodeConstants.grave

        // 修饰键
        static let leftCommand = KeyCodeConstants.leftCommand
        static let rightCommand = KeyCodeConstants.rightCommand
        static let leftShift = KeyCodeConstants.leftShift
        static let rightShift = KeyCodeConstants.rightShift
        static let leftOption = KeyCodeConstants.leftOption
        static let rightOption = KeyCodeConstants.rightOption
        static let leftControl = KeyCodeConstants.leftControl
        static let rightControl = KeyCodeConstants.rightControl
        static let function = KeyCodeConstants.function

        static let modifierKeys = KeyCodeConstants.modifierKeys
        static let functionKeys = KeyCodeConstants.functionKeys
        static let keyMap = KeyCodeConstants.keyMap
    }
}