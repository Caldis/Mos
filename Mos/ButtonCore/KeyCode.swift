//
//  KeyCode.swift
//  Mos
//  键盘和事件相关的常量定义
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

struct KeyCode {
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
    static let function: UInt16 = 63
    static let functionDouble: UInt16 = 179

    static let modifierKeys: Set<UInt16> = [54, 55, 58, 59, 60, 61, 62, 63, 179]

    // F键系列
    static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90] // F1-F20

    // 方向系列
    static let arrowKeys: Set<UInt16> = [126, 125, 123, 124] // 上下左右

    /// 完整键盘映射
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
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        // F区: 不按 FN 时触发的键 (其他录制不到) 而且录制时会自带 FN 的 flag
        160: "F3 (MissionControl)", // 多窗口
        177: "F4 (Spotlight)", // 搜索
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
}
