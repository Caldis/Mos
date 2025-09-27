//
//  SystemShortcut.swift
//  Mos
//  系统快捷键组合常量定义
//  Created by 陈标 on 2025/8/28.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

/// 系统快捷键组合存储结构
/// 使用 快捷键名称 = (修饰键, 主键) 的方式组织
struct SystemShortcut {

    // MARK: - 快捷键数据结构

    /// 快捷键组合结构
    struct Shortcut: Equatable, Hashable {
        let modifiers: NSEvent.ModifierFlags
        let keyCode: UInt16

        init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: UInt16) {
            self.modifiers = modifiers
            self.keyCode = keyCode
        }

        /// Equatable 协议实现
        static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
            return lhs.modifiers == rhs.modifiers && lhs.keyCode == rhs.keyCode
        }

        /// Hashable 协议实现
        func hash(into hasher: inout Hasher) {
            hasher.combine(modifiers.rawValue)
            hasher.combine(keyCode)
        }

        /// 获取快捷键显示名称
        var displayName: String {
            var components: [String] = []

            if modifiers.contains(.control) { components.append("⌃") }
            if modifiers.contains(.option) { components.append("⌥") }
            if modifiers.contains(.shift) { components.append("⇧") }
            if modifiers.contains(.command) { components.append("⌘") }
            if modifiers.contains(.function) { components.append("Fn") }

            if let keyName = KeyCode.keyMap[keyCode] {
                components.append(keyName)
            } else {
                components.append("Unknown(\(keyCode))")
            }

            return components.joined()
        }
    }

    // MARK: - 快捷键
    // 窗口管理
    static let minimizeWindow = Shortcut(.command, 46)             // ⌘M
    static let hideApplication = Shortcut(.command, 4)             // ⌘H
    static let hideOthers = Shortcut([.command, .option], 4)       // ⌘⌥H
    static let nextWindow = Shortcut(.command, 50)                 // ⌘`
    static let closeWindow = Shortcut(.command, 13)                // ⌘W
    static let closeAllWindows = Shortcut([.command, .option], 13) // ⌘⌥W

    // 应用切换
    static let switchApp = Shortcut(.command, 48)                  // ⌘Tab
    static let switchAppReverse = Shortcut([.command, .shift], 48) // ⌘⇧Tab

    // 系统功能
    static let spotlight = Shortcut(.command, 49)                  // ⌘Space
    static let forceQuit = Shortcut([.command, .option], 53)       // ⌘⌥Esc
    static let lockScreen = Shortcut([.command, .control], 12)     // ⌘⌃Q
    static let screenshot = Shortcut([.command, .shift], 20)       // ⌘⇧3
    static let screenshotSelection = Shortcut([.command, .shift], 21)       // ⌘⇧4
    static let screenshotWindow = Shortcut([.command, .shift, .option], 21) // ⌘⇧⌥4
    static let showDesktop = Shortcut(.function, 103)              // F11/Mission Control
    static let moveSpaceLeft = Shortcut(.control, 123)             // ⌃← (暂不可用
    static let moveSpaceRight = Shortcut(.control, 124)            // ⌃→ (暂不可用

    // F键快捷键
    static let missionControl = Shortcut(.function, 160)           // F3/Mission Control
    static let appExpose = Shortcut(.function, 131)                // F4/App Exposé (老款键盘)
    static let spotlight_fn = Shortcut(.function, 177)             // F4/Spotlight (新款键盘)
    static let dictation = Shortcut(.function, 176)                // F5/听写
    static let doNotDisturb = Shortcut(.function, 178)             // F6/勿扰模式

    // MARK: - 辅助方法

    /// 所有系统快捷键的集合
    static let allShortcuts: [String: Shortcut] = [
        // 窗口管理
        "minimizeWindow": minimizeWindow, "hideApplication": hideApplication,
        "hideOthers": hideOthers, "nextWindow": nextWindow, "closeWindow": closeWindow,
        "closeAllWindows": closeAllWindows,

        // 应用切换
        "switchApp": switchApp, "switchAppReverse": switchAppReverse,

        // 系统功能
        "spotlight": spotlight, "forceQuit": forceQuit, "lockScreen": lockScreen,
        "screenshot": screenshot, "screenshotSelection": screenshotSelection,
        "screenshotWindow": screenshotWindow, "showDesktop": showDesktop,
        "moveSpaceLeft": moveSpaceLeft, "moveSpaceRight": moveSpaceRight,

        // F键
        "missionControl": missionControl, "appExpose": appExpose,
        "spotlight_fn": spotlight_fn, "dictation": dictation, "doNotDisturb": doNotDisturb
    ]

    /// 根据修饰键和按键代码查找快捷键名称
    static func findShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String? {
        for (name, shortcut) in allShortcuts {
            if shortcut.modifiers == modifiers && shortcut.keyCode == keyCode {
                return name
            }
        }
        return nil
    }

    /// 根据名称获取快捷键
    static func getShortcut(named: String) -> Shortcut? {
        return allShortcuts[named]
    }

    /// 检查给定的快捷键是否与系统快捷键冲突
    static func isSystemShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        return findShortcut(modifiers: modifiers, keyCode: keyCode) != nil
    }

    /// 获取所有快捷键名称列表
    static var allShortcutNames: [String] {
        return Array(allShortcuts.keys).sorted()
    }

    /// 按类别分组的快捷键
    static let shortcutsByCategory: [String: [String: Shortcut]] = [
        "窗口管理": [
            "minimizeWindow": minimizeWindow, "hideApplication": hideApplication,
            "hideOthers": hideOthers, "nextWindow": nextWindow, "closeWindow": closeWindow,
            "closeAllWindows": closeAllWindows
        ],
        "应用切换": [
            "switchApp": switchApp, "switchAppReverse": switchAppReverse
        ],
        "系统功能": [
            "spotlight": spotlight, "forceQuit": forceQuit, "lockScreen": lockScreen,
            "screenshot": screenshot, "screenshotSelection": screenshotSelection,
            "screenshotWindow": screenshotWindow, "showDesktop": showDesktop,
            "moveSpaceLeft": moveSpaceLeft, "moveSpaceRight": moveSpaceRight
        ],
        "F键": [
            "missionControl": missionControl, "appExpose": appExpose,
            "spotlight_fn": spotlight_fn, "dictation": dictation, "doNotDisturb": doNotDisturb
        ]
    ]
}
