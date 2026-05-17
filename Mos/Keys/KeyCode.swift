//
//  KeyCode.swift
//  Mos
//  键盘和事件相关的常量定义
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

struct KeyCode {
    /// 修饰键
    static let commandL: UInt16 = 55
    static let commandR: UInt16 = 54
    static let shiftL: UInt16 = 56
    static let shiftR: UInt16 = 60
    static let optionL: UInt16 = 58
    static let optionR: UInt16 = 61
    static let controlL: UInt16 = 59
    static let controlR: UInt16 = 62
    static let fnL: UInt16 = 63
    static let fnR: UInt16 = 179
    static let commandKeys: Set<UInt16> = [KeyCode.commandL, KeyCode.commandR]
    static let shiftKeys: Set<UInt16> = [KeyCode.shiftL, KeyCode.shiftR]
    static let optionKeys: Set<UInt16> = [KeyCode.optionL, KeyCode.optionR]
    static let controlKeys: Set<UInt16> = [KeyCode.controlL, KeyCode.controlR]
    static let fnKeys: Set<UInt16> = [KeyCode.fnL, KeyCode.fnR]
    static let modifierKeys: Set<UInt16> = [
        KeyCode.controlL,
        KeyCode.controlR,
        KeyCode.optionL,
        KeyCode.optionR,
        KeyCode.commandL,
        KeyCode.commandR,
        KeyCode.shiftL,
        KeyCode.shiftR,
        KeyCode.fnL,
        KeyCode.fnR
    ]
    static let modifierLKeys = [KeyCode.controlL, KeyCode.optionL, KeyCode.commandL, KeyCode.shiftL]
    static let modifierRKeys = [KeyCode.controlL, KeyCode.optionL, KeyCode.commandL, KeyCode.shiftL]
    // 掩码
    static let modifiersMask: UInt64 =
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskShift.rawValue
    static let keyCodeToMask: [UInt16: CGEventFlags] = [
        KeyCode.controlL: .maskControl,
        KeyCode.controlR: .maskControl,
        KeyCode.optionL: .maskAlternate,
        KeyCode.optionR: .maskAlternate,
        KeyCode.commandL: .maskCommand,
        KeyCode.commandR: .maskCommand,
        KeyCode.shiftL: .maskShift,
        KeyCode.shiftR: .maskShift,
        KeyCode.fnL: .maskSecondaryFn,
        KeyCode.fnR: .maskSecondaryFn,
    ]
    static func getKeyMask(_ keyCode: UInt16) -> CGEventFlags {
        return keyCodeToMask[keyCode] ?? CGEventFlags(rawValue: 0)
    }

    /// F键系列
    static let F1: UInt16 = 122
    static let F2: UInt16 = 120
    static let F3: UInt16 = 99
    static let F4: UInt16 = 118
    static let F5: UInt16 = 96
    static let F6: UInt16 = 97
    static let F7: UInt16 = 98
    static let F8: UInt16 = 100
    static let F9: UInt16 = 101
    static let F10: UInt16 = 109
    static let F11: UInt16 = 103
    static let F12: UInt16 = 111
    static let F13: UInt16 = 105
    static let F14: UInt16 = 107
    static let F15: UInt16 = 113
    static let F16: UInt16 = 106
    static let F17: UInt16 = 64
    static let F18: UInt16 = 79
    static let F19: UInt16 = 80
    static let F20: UInt16 = 90
    static let functionKeys: Set<UInt16> = [
        KeyCode.F1,
        KeyCode.F2,
        KeyCode.F3,
        KeyCode.F4,
        KeyCode.F5,
        KeyCode.F6,
        KeyCode.F7,
        KeyCode.F8,
        KeyCode.F9,
        KeyCode.F10,
        KeyCode.F11,
        KeyCode.F12,
        KeyCode.F13,
        KeyCode.F14,
        KeyCode.F15,
        KeyCode.F16,
        KeyCode.F17,
        KeyCode.F18,
        KeyCode.F19,
        KeyCode.F20
    ]

    /// 方向系列
    static let arrowUp: UInt16 = 126
    static let arrowDown: UInt16 = 125
    static let arrowLeft: UInt16 = 123
    static let arrowRight: UInt16 = 124
    static let arrowKeys: Set<UInt16> = [
        KeyCode.arrowUp,
        KeyCode.arrowDown,
        KeyCode.arrowLeft,
        KeyCode.arrowRight
    ]

    /// 其他
    static let escape: UInt16 = 53

    /// 键盘字符映射
    /// https://eastmanreference.com/complete-list-of-applescript-key-codes
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
        49: "⎵", 51: "⌫", 53: "⎋", 76: "↩", 36: "↩", 48: "↹", 57: "CapsLock",
        // F区
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        // F区: 不按 FN 时触发的键 (其他录制不到) 而且录制时会自带 FN 的 flag
        160: "F3 (MissionControl)", // 调度中心
        177: "F4 (Spotlight)", // 搜索
        131: "F4 (AppExposé)", // 显示所有窗口 (新款的键盘这个位置都是 Spotlight 了
        176: "F5 (Dictating)", // 听写
        178: "F6 (DND)", // 勿扰
        // Direction
        126: "↑", 125: "↓", 123: "←", 124: "→",
        // Navigation (FN + Direction)
        116: "PageUp", 121: "PageDown", 115: "Home", 119: "End",
        // Modifier keys
        63: "Fn", 59: "⌃", 58: "⌥", 55: "⌘", 56: "⇧",
        62: "⌃ (R)", 61: "⌥ (R)", 54: "⌘ (R)", 60: "⇧ (R)", // 键盘不会直接触发这些右侧修饰键, 但是系统预留了
        179: "Fn (179)", // 179 可以通过双击 FN 触发
    ]

    /// 鼠标字符映射
    static let mouseMap: [UInt16: String] = [
        // 主要
        0: "🖱L", 1: "🖱R", 2: "🖱M",
        // 其他鼠标按键
        3: "🖱️ Back Button", 4: "🖱️ Forward Button", 5: "🖱5", 6: "🖱6", 7: "🖱7", 8: "🖱8",
        9: "🖱9", 10: "🖱10", 11: "🖱11", 12: "🖱12", 13: "🖱13",
        14: "🖱14", 15: "🖱15", 16: "🖱16", 17: "🖱17", 18: "🖱18",
        19: "🖱19", 20: "🖱20",
    ]
    static let mouseMainKeys: [UInt16] = [0,1]  // Only protect left/right clicks, allow middle button without modifiers
}
