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
        let identifier: String  // 本地化键名(如 "minimizeWindow")
        let code: UInt16
        let modifiers: NSEvent.ModifierFlags

        init(_ identifier: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags) {
            self.identifier = identifier
            self.code = code
            self.modifiers = modifiers
        }

        /// 获取本地化显示名称
        var localizedName: String {
            return NSLocalizedString(identifier, comment: "")
        }

        /// 获取 SF Symbol 图标名称 (macOS 11.0+)
        var symbolName: String {
            switch identifier {
            // 窗口管理
            case "minimizeWindow": return "minus.rectangle"
            case "hideApplication": return "eye.slash"
            case "hideOthers": return "eye.slash.circle"
            case "nextWindow": return "arrow.right.square"
            case "closeWindow": return "xmark.rectangle"
            case "closeAllWindows": return "xmark.circle.fill"
            // 应用切换
            case "switchApp": return "arrow.right.circle"
            case "switchAppReverse": return "arrow.left.circle"
            // 系统功能
            case "spotlight": return "magnifyingglass"
            case "forceQuit": return "exclamationmark.triangle"
            case "lockScreen": return "lock.shield"
            case "screenshot": return "camera.viewfinder"
            case "screenshotSelection": return "viewfinder.rectangular"
            case "showDesktop": return "rectangle.on.rectangle"
            case "moveSpaceLeft": return "arrow.left.to.line"
            case "moveSpaceRight": return "arrow.right.to.line"
            // 功能键
            case "missionControl": return "square.grid.3x2"
            case "appExpose": return "square.grid.3x3"
            case "spotlightFn": return "magnifyingglass.circle"
            case "dictation": return "mic"
            case "doNotDisturb": return "moon"
            default: return "questionmark.circle"
            }
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
    static let minimizeWindow = Shortcut("minimizeWindow", 46, .command)
    static let hideApplication = Shortcut("hideApplication", 4, .command)
    static let hideOthers = Shortcut("hideOthers", 4, [.command, .option])
    static let nextWindow = Shortcut("nextWindow", 50, .command)
    static let closeWindow = Shortcut("closeWindow", 13, .command)
    static let closeAllWindows = Shortcut("closeAllWindows", 13, [.command, .option])

    // 应用切换
    static let switchApp = Shortcut("switchApp", 48, .command)
    static let switchAppReverse = Shortcut("switchAppReverse", 48, [.command, .shift])

    // 系统功能
    static let spotlight = Shortcut("spotlight", 49, .command)
    static let forceQuit = Shortcut("forceQuit", 53, [.command, .option])
    static let lockScreen = Shortcut("lockScreen", 12, [.command, .control])
    static let screenshot = Shortcut("screenshot", 20, [.command, .shift])
    static let screenshotSelection = Shortcut("screenshotSelection", 21, [.command, .shift])
    static let showDesktop = Shortcut("showDesktop", 103, .function)
    static let moveSpaceLeft = Shortcut("moveSpaceLeft", 123, .control)
    static let moveSpaceRight = Shortcut("moveSpaceRight", 124, .control)

    // F键快捷键
    static let missionControl = Shortcut("missionControl", 160, .function)
    static let appExpose = Shortcut("appExpose", 131, .function)
    static let spotlight_fn = Shortcut("spotlightFn", 177, .function)
    static let dictation = Shortcut("dictation", 176, .function)
    static let doNotDisturb = Shortcut("doNotDisturb", 178, .function)

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
        "showDesktop": showDesktop, "moveSpaceLeft": moveSpaceLeft, "moveSpaceRight": moveSpaceRight,

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
        "categoryWindowManagement": [
            minimizeWindow, hideApplication, hideOthers, nextWindow, closeWindow, closeAllWindows
        ],
        "categoryAppSwitching": [
            switchApp, switchAppReverse
        ],
        "categorySystemFunctions": [
            spotlight, forceQuit, lockScreen, screenshot, screenshotSelection,
            showDesktop, moveSpaceLeft, moveSpaceRight
        ],
        "categoryFunctionKeys": [
            missionControl, appExpose, spotlight_fn, dictation, doNotDisturb
        ]
    ]

    /// 获取分类的本地化名称
    static func localizedCategoryName(_ categoryIdentifier: String) -> String {
        return NSLocalizedString(categoryIdentifier, comment: "")
    }

    /// 获取分类的 SF Symbol 图标名称 (macOS 11.0+)
    static func categorySymbolName(_ categoryIdentifier: String) -> String {
        switch categoryIdentifier {
        case "categoryWindowManagement": return "macwindow"
        case "categoryAppSwitching": return "arrow.left.arrow.right"
        case "categorySystemFunctions": return "gearshape"
        case "categoryFunctionKeys": return "keyboard"
        default: return "folder"
        }
    }
}
