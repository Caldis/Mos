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

    // MARK: - 鼠标导航事件标记

    /// 合成导航鼠标事件的标记值，用于在 ButtonCore 中识别并跳过 Mos 自身合成的事件，避免无限循环
    /// 值为 ASCII 字符串 "MOSNAV" 的十六进制编码: M=0x4D O=0x4F S=0x53 N=0x4E A=0x41 V=0x56
    static let mosNavigationEventMarker: Int64 = 0x4D4F534E4156

    /// 判断事件是否为 Mos 合成的导航鼠标事件
    static func isMosNavigationEvent(_ event: CGEvent) -> Bool {
        return event.getIntegerValueField(.eventSourceUserData) == mosNavigationEventMarker
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
        // 后退/前进导航使用鼠标按钮事件，与键盘布局无关，兼容所有应用 (浏览器、Finder、VSCode 等)
        switch shortcutName {
        case "navigateBack":
            executeMouseNavigation(isBack: true)
            return
        case "navigateForward":
            executeMouseNavigation(isBack: false)
            return
        default:
            break
        }

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

    // MARK: - 鼠标导航事件

    /// 发送标准 macOS 鼠标后退/前进按钮事件
    ///
    /// 使用鼠标按钮 3 (后退) / 4 (前进) 而非键盘快捷键，兼容所有支持鼠标导航的应用
    /// (如 Safari、Chrome、Finder、VSCode 等)，且不受键盘布局影响。
    ///
    /// - Parameter isBack: `true` 发送后退 (按钮3)，`false` 发送前进 (按钮4)
    private func executeMouseNavigation(isBack: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // macOS 标准后退按钮 = 3 (X1)，前进按钮 = 4 (X2)
        let buttonNumber: Int64 = isBack ? 3 : 4

        // 将 NSEvent 坐标 (左下角原点) 转换为 CGEvent 坐标 (左上角原点)
        let mouseLocation = NSEvent.mouseLocation
        guard let screenHeight = NSScreen.main?.frame.height else { return }
        let position = CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)

        // 发送 mouseDown 事件
        // macOS 的 CGMouseButton 枚举仅定义 .left/.right/.center (0-2)。
        // 对于按钮编号 3 和 4，需使用 .center 作为占位参数创建事件，
        // 再通过 mouseEventButtonNumber 字段覆盖实际按钮编号。
        // (CGEvent API 限制：无法直接传入 3/4 作为 CGMouseButton 参数)
        if let mouseDown = CGEvent(otherEventSource: source, type: .otherMouseDown,
                                   mouseCursorPosition: position, mouseButton: .center) {
            mouseDown.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
            mouseDown.setIntegerValueField(.eventSourceUserData, value: ShortcutExecutor.mosNavigationEventMarker)
            mouseDown.post(tap: .cghidEventTap)
        }

        // 发送 mouseUp 事件
        if let mouseUp = CGEvent(otherEventSource: source, type: .otherMouseUp,
                                 mouseCursorPosition: position, mouseButton: .center) {
            mouseUp.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
            mouseUp.setIntegerValueField(.eventSourceUserData, value: ShortcutExecutor.mosNavigationEventMarker)
            mouseUp.post(tap: .cghidEventTap)
        }
    }
}
