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

    // MARK: - 执行快捷键

    /// 执行系统快捷键
    /// - Parameter shortcutName: 快捷键名称 (如 "minimizeWindow")
    func execute(_ shortcutName: String) {
        // 优先使用系统实际配置 (对于Mission Control相关快捷键)
        if let resolved = SystemShortcut.resolveSystemShortcut(shortcutName) {
            NSLog("ShortcutExecutor: Using system config for '\(shortcutName)' (code: \(resolved.code), modifiers: 0x\(String(resolved.modifiers, radix: 16)))")
            executeWithRawFlags(code: resolved.code, modifiers: resolved.modifiers)
            return
        }

        // Fallback到内置快捷键定义
        guard let shortcut = SystemShortcut.getShortcut(named: shortcutName) else {
            NSLog("ShortcutExecutor: Unknown shortcut '\(shortcutName)'")
            return
        }

        NSLog("ShortcutExecutor: Executing '\(shortcutName)' (code: \(shortcut.code), modifiers: \(shortcut.modifiers))")
        executeWithRawFlags(code: shortcut.code, modifiers: UInt64(shortcut.modifiers.rawValue))
    }

    // MARK: - Private Implementation

    /// 使用原始flags值发送快捷键事件
    /// - Parameters:
    ///   - code: 虚拟键码
    ///   - modifiers: 修饰键flags (直接从symbolichotkeys读取的原始值)
    private func executeWithRawFlags(code: CGKeyCode, modifiers: UInt64) {
        // 创建事件源
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            NSLog("ShortcutExecutor: Failed to create event source")
            return
        }

        // 发送按键按下事件
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            keyDown.flags = CGEventFlags(rawValue: modifiers)
            keyDown.post(tap: .cghidEventTap)
        }

        // 发送按键抬起事件
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
