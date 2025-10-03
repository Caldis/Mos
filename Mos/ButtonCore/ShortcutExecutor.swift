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
    init() {}

    // MARK: - 执行快捷键

    /// 执行系统快捷键
    /// - Parameter shortcutName: 快捷键名称 (如 "minimizeWindow")
    func execute(_ shortcutName: String) {
        // 获取快捷键定义
        guard let shortcut = SystemShortcut.getShortcut(named: shortcutName) else {
            NSLog("ShortcutExecutor: Unknown shortcut '\(shortcutName)'")
            return
        }

        NSLog("ShortcutExecutor: Executing '\(shortcutName)' (code: \(shortcut.code), modifiers: \(shortcut.modifiers))")

        // 创建事件源
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            NSLog("ShortcutExecutor: Failed to create event source")
            return
        }

        // 发送按键按下事件
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.code, keyDown: true) {
            keyDown.flags = CGEventFlags(rawValue: UInt64(shortcut.modifiers.rawValue))
            keyDown.post(tap: .cghidEventTap)
        }

        // 发送按键抬起事件
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.code, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
