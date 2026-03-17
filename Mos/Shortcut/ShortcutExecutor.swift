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
    /// - Parameter shortcutName: 快捷键名称 (如 "minimizeWindow", "mouseLeftClick", "logiSmartShiftToggle")
    func execute(named shortcutName: String) {
        // 鼠标按键动作
        if shortcutName.hasPrefix("mouse") {
            executeMouseAction(shortcutName)
            return
        }

        // Logi HID++ 动作
        if shortcutName.hasPrefix("logi") {
            executeLogiAction(shortcutName)
            return
        }

        // 优先使用系统实际配置 (对于Mission Control相关快捷键)
        if let resolved = SystemShortcut.resolveSystemShortcut(shortcutName) {
            execute(code: resolved.code, flags: resolved.modifiers)
            return
        }

        // Fallback到内置快捷键定义
        guard let shortcut = SystemShortcut.getShortcut(named: shortcutName) else {
            return
        }

        execute(shortcut)
    }

    // MARK: - Mouse Actions

    /// 执行鼠标按键动作
    private func executeMouseAction(_ name: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let location = NSEvent.mouseLocation
        // 转换坐标: NSEvent 用左下角原点, CGEvent 用左上角原点
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

        switch name {
        case "mouseLeftClick":
            postMouseClick(source: source, at: cgPoint, button: .left,
                          downType: .leftMouseDown, upType: .leftMouseUp)
        case "mouseRightClick":
            postMouseClick(source: source, at: cgPoint, button: .right,
                          downType: .rightMouseDown, upType: .rightMouseUp)
        case "mouseMiddleClick":
            postMouseClick(source: source, at: cgPoint, button: .center,
                          downType: .otherMouseDown, upType: .otherMouseUp, buttonNumber: 2)
        case "mouseBackClick":
            postMouseClick(source: source, at: cgPoint, button: .center,
                          downType: .otherMouseDown, upType: .otherMouseUp, buttonNumber: 3)
        case "mouseForwardClick":
            postMouseClick(source: source, at: cgPoint, button: .center,
                          downType: .otherMouseDown, upType: .otherMouseUp, buttonNumber: 4)
        default:
            break
        }
    }

    /// 发送鼠标点击事件 (down + up)
    private func postMouseClick(source: CGEventSource, at point: CGPoint,
                                button: CGMouseButton, downType: CGEventType, upType: CGEventType,
                                buttonNumber: Int64? = nil) {
        if let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button) {
            if let bn = buttonNumber { down.setIntegerValueField(.mouseEventButtonNumber, value: bn) }
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button) {
            if let bn = buttonNumber { up.setIntegerValueField(.mouseEventButtonNumber, value: bn) }
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Logi HID++ Actions

    /// 执行 Logitech HID++ 动作
    private func executeLogiAction(_ name: String) {
        switch name {
        case "logiSmartShiftToggle":
            LogitechHIDManager.shared.executeSmartShiftToggle()
        case "logiDPICycleUp":
            LogitechHIDManager.shared.executeDPICycle(direction: .up)
        case "logiDPICycleDown":
            LogitechHIDManager.shared.executeDPICycle(direction: .down)
        default:
            break
        }
    }
}
