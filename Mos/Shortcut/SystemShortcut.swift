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
        let minimumVersion: OperatingSystemVersion?  // 最低系统版本要求(可选)

        init(_ identifier: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags, minimumVersion: OperatingSystemVersion? = nil) {
            self.identifier = identifier
            self.code = code
            self.modifiers = modifiers
            self.minimumVersion = minimumVersion
        }

        /// 检查当前系统是否支持此快捷键
        var isAvailable: Bool {
            guard let minVersion = minimumVersion else { return true }
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(minVersion)
        }

        /// 获取本地化显示名称
        var localizedName: String {
            return NSLocalizedString(identifier, comment: "")
        }

        /// 获取 SF Symbol 图标名称 (macOS 11.0+)
        var symbolName: String {
            switch identifier {
                // 功能键
                case "missionControl": return "square.grid.3x2"
                case "appExpose": return "square.grid.3x3"
                case "spotlightSys": return "magnifyingglass.circle"
                case "dictation": return "mic"
                case "doNotDisturb": return "moon"
                case "showDesktop": return "rectangle.on.rectangle"
                // 应用切换
                case "switchApp": return "arrow.right.circle"
                case "switchAppReverse": return "arrow.left.circle"
                // 文档编辑
                case "copy": return "doc.on.doc"
                case "paste": return "doc.on.clipboard"
                case "cut": return "scissors"
                case "undo": return "arrow.uturn.backward"
                case "redo": return "arrow.uturn.forward"
                case "selectAll": return "selection.pin.in.out"
                case "find": return "magnifyingglass"
                case "bold": return "bold"
                case "italic": return "italic"
                case "underline": return "underline"
                // Finder 操作
                case "newFinderWindow": return "macwindow.badge.plus"
                case "moveToTrash": return "trash"
                case "emptyTrash": return "trash.slash"
                case "duplicateFile": return "plus.square.on.square"
                case "getInfo": return "info.circle"
                case "newFolder": return "folder.badge.plus"
                case "goToFolder": return "folder.badge.gearshape"
                case "viewAsIcons": return "square.grid.2x2"
                case "viewAsList": return "list.bullet"
                case "viewAsColumns": return "rectangle.split.3x1"
                case "viewAsGallery": return "square.grid.3x3.fill.square"
                // 系统控制
                case "spotlight": return "magnifyingglass"
                case "characterViewer": return "face.smiling"
                case "forceQuit": return "exclamationmark.triangle"
                case "lockScreen": return "lock.shield"
                case "logout": return "rectangle.portrait.and.arrow.right"
                case "shutdownDialog": return "power"
                case "screenshot": return "camera.viewfinder"
                case "screenshotSelection": return "viewfinder.rectangular"
                case "screenshotAndRecording": return "camera.metering.center.weighted"
                case "moveSpaceLeft": return "arrow.left.to.line"
                case "moveSpaceRight": return "arrow.right.to.line"
                // 窗口管理
                case "minimizeWindow": return "minus.rectangle"
                case "hideApplication": return "eye.slash"
                case "hideOthers": return "eye.slash.circle"
                case "nextWindow": return "arrow.right.square"
                case "closeWindow": return "xmark.rectangle"
                case "closeAllWindows": return "xmark.circle.fill"
                case "quitApp": return "power.circle"
                // 辅助功能
                case "invertColors": return "circle.lefthalf.filled.inverse"
                case "zoomIn": return "plus.magnifyingglass"
                case "zoomOut": return "minus.magnifyingglass"
                // 其他
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
    // 功能键
    static let missionControl = Shortcut("missionControl", 160, .function)
    static let appExpose = Shortcut("appExpose", 131, .function)
    static let spotlightSys = Shortcut("spotlightSys", 177, .function)
    static let dictation = Shortcut("dictation", 176, .function)
    static let doNotDisturb = Shortcut("doNotDisturb", 178, .function)
    static let showDesktop = Shortcut("showDesktop", 103, .function)

    // 应用切换
    static let switchApp = Shortcut("switchApp", 48, .command)
    static let switchAppReverse = Shortcut("switchAppReverse", 48, [.command, .shift])

    // 文档编辑
    static let copy = Shortcut("copy", 8, .command)  // Command-C
    static let paste = Shortcut("paste", 9, .command)  // Command-V
    static let cut = Shortcut("cut", 7, .command)  // Command-X
    static let undo = Shortcut("undo", 6, .command)  // Command-Z
    static let redo = Shortcut("redo", 6, [.command, .shift])  // Command-Shift-Z
    static let selectAll = Shortcut("selectAll", 0, .command)  // Command-A
    static let find = Shortcut("find", 3, .command)  // Command-F
    static let bold = Shortcut("bold", 11, .command)  // Command-B
    static let italic = Shortcut("italic", 34, .command)  // Command-I
    static let underline = Shortcut("underline", 32, .command)  // Command-U

    // Finder 操作
    static let newFinderWindow = Shortcut("newFinderWindow", 45, .command)  // Command-N
    static let moveToTrash = Shortcut("moveToTrash", 51, .command)  // Command-Delete
    static let emptyTrash = Shortcut("emptyTrash", 51, [.command, .shift])  // Command-Shift-Delete
    static let duplicateFile = Shortcut("duplicateFile", 2, .command)  // Command-D
    static let getInfo = Shortcut("getInfo", 34, [.command])  // Command-I (Finder only, conflicts with italic)
    static let newFolder = Shortcut("newFolder", 45, [.command, .shift])  // Command-Shift-N
    static let goToFolder = Shortcut("goToFolder", 5, [.command, .shift])  // Command-Shift-G
    static let viewAsIcons = Shortcut("viewAsIcons", 18, .command)  // Command-1
    static let viewAsList = Shortcut("viewAsList", 19, .command)  // Command-2
    static let viewAsColumns = Shortcut("viewAsColumns", 20, .command)  // Command-3
    static let viewAsGallery = Shortcut("viewAsGallery", 21, .command)  // Command-4

    // 系统控制
    static let spotlight = Shortcut("spotlight", 49, .command)  // Command-Space
    static let characterViewer = Shortcut("characterViewer", 49, [.control, .command])  // Control-Command-Space (macOS 10.9+)
    static let forceQuit = Shortcut("forceQuit", 53, [.command, .option])  // Command-Option-Esc
    static let lockScreen = Shortcut("lockScreen", 12, [.command, .control])  // Command-Control-Q
    static let logout = Shortcut("logout", 12, [.command, .shift])  // Command-Shift-Q
    static let shutdownDialog = Shortcut("shutdownDialog", 6, .control)  // Control-Power (mapped to Control-Z as placeholder)
    static let screenshot = Shortcut("screenshot", 20, [.command, .shift])  // Command-Shift-3
    static let screenshotSelection = Shortcut("screenshotSelection", 21, [.command, .shift])  // Command-Shift-4
    static let screenshotAndRecording = Shortcut("screenshotAndRecording", 23, [.command, .shift], minimumVersion: OperatingSystemVersion(majorVersion: 10, minorVersion: 14, patchVersion: 0))  // Command-Shift-5 (macOS 10.14+)
    static let moveSpaceLeft = Shortcut("moveSpaceLeft", 123, [.control, .function])  // Fn-Control-Left
    static let moveSpaceRight = Shortcut("moveSpaceRight", 124, [.control, .function])  // Fn-Control-Right

    // 窗口管理
    static let minimizeWindow = Shortcut("minimizeWindow", 46, .command)  // Command-M
    static let hideApplication = Shortcut("hideApplication", 4, .command)  // Command-H
    static let hideOthers = Shortcut("hideOthers", 4, [.command, .option])  // Command-Option-H
    static let nextWindow = Shortcut("nextWindow", 50, .command)  // Command-`
    static let closeWindow = Shortcut("closeWindow", 13, .command)  // Command-W
    static let closeAllWindows = Shortcut("closeAllWindows", 13, [.command, .option])  // Command-Option-W
    static let quitApp = Shortcut("quitApp", 12, .command)  // Command-Q

    // 辅助功能
    static let invertColors = Shortcut("invertColors", 28, [.command, .option, .control])  // Command-Option-Control-8
    static let zoomIn = Shortcut("zoomIn", 24, [.command, .option])  // Command-Option-=
    static let zoomOut = Shortcut("zoomOut", 27, [.command, .option])  // Command-Option--

    // MARK: - 辅助方法

    /// 所有系统快捷键的集合
    static let allShortcuts: [String: Shortcut] = [
        // 功能键
        "missionControl": missionControl, "appExpose": appExpose,
        "spotlightSys": spotlightSys, "dictation": dictation, "doNotDisturb": doNotDisturb,
        "showDesktop": showDesktop,
        // 应用切换
        "switchApp": switchApp, "switchAppReverse": switchAppReverse,
        // 文档编辑
        "copy": copy, "paste": paste, "cut": cut, "undo": undo, "redo": redo,
        "selectAll": selectAll, "find": find, "bold": bold, "italic": italic, "underline": underline,
        // Finder 操作
        "newFinderWindow": newFinderWindow, "moveToTrash": moveToTrash, "emptyTrash": emptyTrash,
        "duplicateFile": duplicateFile, "getInfo": getInfo, "newFolder": newFolder, "goToFolder": goToFolder,
        "viewAsIcons": viewAsIcons, "viewAsList": viewAsList, "viewAsColumns": viewAsColumns, "viewAsGallery": viewAsGallery,
        // 系统控制
        "spotlight": spotlight, "characterViewer": characterViewer,
        "forceQuit": forceQuit, "lockScreen": lockScreen, "logout": logout,
        "shutdownDialog": shutdownDialog, "screenshot": screenshot, "screenshotSelection": screenshotSelection,
        "screenshotAndRecording": screenshotAndRecording,
        "moveSpaceLeft": moveSpaceLeft, "moveSpaceRight": moveSpaceRight,
        // 窗口管理
        "minimizeWindow": minimizeWindow, "hideApplication": hideApplication,
        "hideOthers": hideOthers, "nextWindow": nextWindow, "closeWindow": closeWindow,
        "closeAllWindows": closeAllWindows, "quitApp": quitApp,
        // 辅助功能
        "invertColors": invertColors, "zoomIn": zoomIn, "zoomOut": zoomOut,
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

    /// 按类别分组的快捷键 (有序数组,顺序即菜单显示顺序)
    static let shortcutsByCategory: [(category: String, shortcuts: [Shortcut])] = [
        ("categoryFunctionKeys", [
            missionControl, appExpose, spotlightSys, dictation, doNotDisturb, showDesktop,
            moveSpaceLeft, moveSpaceRight
        ]),
        ("categoryAppsAndWindows", [
            switchApp, switchAppReverse,
            minimizeWindow, hideApplication, hideOthers, nextWindow, closeWindow, closeAllWindows, quitApp
        ]),
        ("categoryDocumentEditing", [
            copy, paste, cut, undo, redo, selectAll, find, bold, italic, underline
        ]),
        ("categoryFinderActions", [
            newFinderWindow, moveToTrash, emptyTrash, duplicateFile, getInfo, newFolder, goToFolder,
            viewAsIcons, viewAsList, viewAsColumns, viewAsGallery
        ]),
        ("categorySystem", [
            spotlight, characterViewer, forceQuit, lockScreen, logout, shutdownDialog
        ]),
        ("categoryScreenshot", [
            screenshot, screenshotSelection, screenshotAndRecording
        ]),
        // ("categoryAccessibility", [  // 暂时不提供, 有问题
        //     invertColors, zoomIn, zoomOut
        // ]),
    ]

    /// 获取分类的本地化名称
    static func localizedCategoryName(_ categoryIdentifier: String) -> String {
        return NSLocalizedString(categoryIdentifier, comment: "")
    }

    /// 获取分类的 SF Symbol 图标名称 (macOS 11.0+)
    static func categorySymbolName(_ categoryIdentifier: String) -> String {
        switch categoryIdentifier {
        case "categoryFunctionKeys": return "keyboard"
        case "categoryAppsAndWindows": return "macwindow.on.rectangle"
        case "categoryDocumentEditing": return "doc.text"
        case "categoryFinderActions": return "folder"
        case "categorySystem": return "gearshape"
        case "categoryScreenshot": return "camera.viewfinder"
        case "categoryAccessibility": return "eye"
        default: return "questionmark.folder"
        }
    }
}

// MARK: - System Configuration Resolver

/// 从symbolichotkeys动态解析系统快捷键配置
extension SystemShortcut {

    /// 系统快捷键ID映射表 (symbolichotkeys -> 快捷键名称)
    private static let symbolicHotkeyMapping: [Int: String] = [
        79: "moveSpaceLeft",   // Move left a space (default: Control-Left)
        80: "moveSpaceLeft",   // Move left a space with shift modifier
        81: "moveSpaceRight",  // Move right a space (default: Control-Right)
        82: "moveSpaceRight",  // Move right a space with shift modifier
    ]

    /// 缓存的已解析快捷键配置
    private static var resolvedCache: [String: (code: CGKeyCode, modifiers: UInt64)] = {
        loadSystemShortcuts()
    }()

    /// 获取解析后的系统快捷键配置
    /// - Parameter name: 快捷键名称 (如 "moveSpaceLeft")
    /// - Returns: (keyCode, modifiers) 或 nil
    static func resolveSystemShortcut(_ name: String) -> (code: CGKeyCode, modifiers: UInt64)? {
        return resolvedCache[name]
    }

    /// 重新加载系统快捷键配置
    static func reloadSystemShortcuts() {
        resolvedCache = loadSystemShortcuts()
        NSLog("SystemShortcut: Reloaded system config, \(resolvedCache.count) shortcuts resolved")
    }

    /// 从系统配置加载快捷键
    private static func loadSystemShortcuts() -> [String: (code: CGKeyCode, modifiers: UInt64)] {
        var resolved: [String: (code: CGKeyCode, modifiers: UInt64)] = [:]

        // 读取系统快捷键配置
        guard let symbolicHotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotkeys = symbolicHotkeys["AppleSymbolicHotKeys"] as? [String: Any] else {
            NSLog("SystemShortcut: Failed to read com.apple.symbolichotkeys")
            return resolved
        }

        // 解析每个感兴趣的快捷键
        for (hotkeyID, shortcutName) in symbolicHotkeyMapping {
            guard let hotkeyConfig = hotkeys[String(hotkeyID)] as? [String: Any],
                  let enabled = hotkeyConfig["enabled"] as? Bool,
                  enabled,
                  let value = hotkeyConfig["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3 else {
                continue
            }

            // 提取参数
            // parameters[0]: Unicode character (65535 for non-printable)
            // parameters[1]: Virtual key code
            // parameters[2]: Modifier flags
            guard let keyCode = parameters[1] as? Int,
                  let modifiers = parameters[2] as? Int else {
                continue
            }

            // 只保存主快捷键(ID较小的),避免重复
            // Hotkey 79/81 是主快捷键, 80/82 是带额外修饰键的变体
            if hotkeyID == 79 || hotkeyID == 81 {
                if resolved[shortcutName] == nil {
                    resolved[shortcutName] = (CGKeyCode(keyCode), UInt64(modifiers))
                    NSLog("SystemShortcut: Loaded \(shortcutName) = keyCode:\(keyCode), modifiers:0x\(String(modifiers, radix: 16))")
                }
            }
        }

        return resolved
    }
}
