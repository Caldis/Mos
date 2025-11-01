//
//  ShortcutExecutor.swift
//  Mos
//  系统快捷键执行器 - 发送快捷键事件
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class ShortcutExecutor {

    // 单例
    static let shared = ShortcutExecutor()
    init() {
        NSLog("Module initialized: ShortcutExecutor")
    }

    // MARK: - 执行快捷键 (统一接口)

    /// 执行快捷键 (底层接口, 使用原始flags)
    /// - Parameters:
    ///   - code: 虚拟键码
    ///   - flags: 修饰键flags (UInt64原始值)
    ///   - preserveFlagsOnKeyUp: KeyUp 时是否保留修饰键 flags (默认 false)
    func execute(code: CGKeyCode, flags: UInt64, preserveFlagsOnKeyUp: Bool = false) {
        // 创建事件源
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            // NSLog("ShortcutExecutor: Failed to create event source")
            return
        }

        // 发送按键按下事件
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            keyDown.flags = CGEventFlags(rawValue: flags)
            keyDown.post(tap: .cghidEventTap)
        }

        // 发送按键抬起事件
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
            if preserveFlagsOnKeyUp {
                keyUp.flags = CGEventFlags(rawValue: flags)
            }
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// 执行系统快捷键 (从SystemShortcut.Shortcut对象)
    /// - Parameter shortcut: SystemShortcut.Shortcut对象
    func execute(_ shortcut: SystemShortcut.Shortcut) {
        // NSLog("ShortcutExecutor: Executing '\(shortcut.identifier)' (code: \(shortcut.code), modifiers: \(shortcut.modifiers))")
        execute(code: shortcut.code, flags: UInt64(shortcut.modifiers.rawValue), preserveFlagsOnKeyUp: shortcut.preserveFlagsOnKeyUp)
    }

    /// 执行系统快捷键 (从名称解析, 支持动态读取系统配置)
    /// - Parameter shortcutName: 快捷键名称 (如 "minimizeWindow")
    func execute(named shortcutName: String) {
        // 优先使用系统实际配置 (对于Mission Control相关快捷键)
        if let resolved = SystemShortcut.resolveSystemShortcut(shortcutName) {
            // NSLog("ShortcutExecutor: Using system config for '\(shortcutName)' (code: \(resolved.code), modifiers: 0x\(String(resolved.modifiers, radix: 16)))")
            execute(code: resolved.code, flags: resolved.modifiers)
            return
        }

        // Fallback到内置快捷键定义
        guard let shortcut = SystemShortcut.getShortcut(named: shortcutName) else {
            // NSLog("ShortcutExecutor: Unknown shortcut '\(shortcutName)'")
            return
        }

        execute(shortcut)
    }
}
