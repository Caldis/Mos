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
        let name: String
        let code: UInt16
        let modifiers: NSEvent.ModifierFlags

        init(_ name: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags) {
            self.name = name
            self.code = code
            self.modifiers = modifiers
        }

        /// Equatable 协议实现
        static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
            return lhs.code == rhs.code && lhs.modifiers == rhs.modifiers
        }

        /// Hashable 协议实现
        func hash(into hasher: inout Hasher) {
            hasher.combine(modifiers.rawValue)
            hasher.combine(code)
        }

        /// 获取 NSMenuItem 的 keyEquivalent 和 modifierMask
        var keyEquivalent: (keyEquivalent: String, modifierMask: NSEvent.ModifierFlags) {
            // 对于 Function 键，不设置 keyEquivalent，避免显示问题
            if modifiers.contains(.function) {
                return ("", [])
            }

            // 获取主键字符
            var keyEquivalent = ""
            if let keyName = KeyCode.keyMap[code] {
                // 对于字母键使用小写
                if keyName.count == 1 && keyName.rangeOfCharacter(from: .letters) != nil {
                    keyEquivalent = keyName.lowercased()
                } else {
                    // 对于特殊键（如空格、回车等）保持原样
                    keyEquivalent = keyName
                }
            }

            // 转换修饰键
            var modifierMask: NSEvent.ModifierFlags = []
            if modifiers.contains(.command) {
                modifierMask.insert(.command)
            }
            if modifiers.contains(.shift) {
                modifierMask.insert(.shift)
            }
            if modifiers.contains(.option) {
                modifierMask.insert(.option)
            }
            if modifiers.contains(.control) {
                modifierMask.insert(.control)
            }

            return (keyEquivalent, modifierMask)
        }
    }

    // MARK: - 快捷键
    // 窗口管理
    static let minimizeWindow = Shortcut("Minimize Window", 46, .command)
    static let hideApplication = Shortcut("Hide Application", 4, .command)
    static let hideOthers = Shortcut("Hide Others", 4, [.command, .option])
    static let nextWindow = Shortcut("Next Window", 50, .command)
    static let closeWindow = Shortcut("Close Window", 13, .command)
    static let closeAllWindows = Shortcut("Close All Windows", 13, [.command, .option])

    // 应用切换
    static let switchApp = Shortcut("Switch Application", 48, .command)
    static let switchAppReverse = Shortcut("Switch Application Reverse", 48, [.command, .shift])

    // 系统功能
    static let spotlight = Shortcut("Spotlight Search", 49, .command)
    static let forceQuit = Shortcut("Force Quit", 53, [.command, .option])
    static let lockScreen = Shortcut("Lock Screen", 12, [.command, .control])
    static let screenshot = Shortcut("Screenshot", 20, [.command, .shift])
    static let screenshotSelection = Shortcut("Screenshot Selection", 21, [.command, .shift])
    static let screenshotWindow = Shortcut("Screenshot Window", 21, [.command, .shift, .option])
    static let showDesktop = Shortcut("Show Desktop", 103, .function)
    static let moveSpaceLeft = Shortcut("Move Space Left", 123, .control)
    static let moveSpaceRight = Shortcut("Move Space Right", 124, .control)

    // F键快捷键
    static let missionControl = Shortcut("Mission Control", 160, .function)
    static let appExpose = Shortcut("Launchpad", 131, .function)
    static let spotlight_fn = Shortcut("Spotlight Search", 177, .function)
    static let dictation = Shortcut("Dictation", 176, .function)
    static let doNotDisturb = Shortcut("Do Not Disturb", 178, .function)

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
            if shortcut.modifiers == modifiers && shortcut.code == keyCode {
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
    static let shortcutsByCategory: [String: [Shortcut]] = [
        "Window Management": [
            minimizeWindow, hideApplication, hideOthers, nextWindow, closeWindow, closeAllWindows
        ],
        "App Switching": [
            switchApp, switchAppReverse
        ],
        "System Functions": [
            spotlight, forceQuit, lockScreen, screenshot, screenshotSelection,
            screenshotWindow, showDesktop, moveSpaceLeft, moveSpaceRight
        ],
        "Function Keys": [
            missionControl, appExpose, spotlight_fn, dictation, doNotDisturb
        ]
    ]
}
