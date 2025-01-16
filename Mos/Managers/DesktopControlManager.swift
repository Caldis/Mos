//
//  MissionControlManager.swift
//  Mos
//
//  Created by Caldis on 2025/1/16.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

final class DesktopControlManager {
    // MARK: - Singleton
    static let shared = DesktopControlManager()
    private init() {}
    
    // MARK: - Types
    enum DesktopControlError: Error {
        case shortcutNotFound
        case eventSourceCreationFailed
        case accessibilityNotAuthorized
    }
    
    // MARK: - Public Methods
    func toggleMissionControl() throws {
        // 尝试使用系统配置的快捷键
        if let shortcut = getMissionControlShortcut() {
            print("getMissionControlShortcut", shortcut)
            simulateKeyPress(shortcut: shortcut)
            return
        }
        
        // 回退到默认的 Mission Control 键
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw DesktopControlError.eventSourceCreationFailed
        }
        print("fallback to MacKeyCode.missionControl", MacKeyCode.missionControl.rawValue)
        simulateKeyPress(keyCode: MacKeyCode.missionControl.rawValue, source: source)
    }
    
    func toggleLaunchpad() throws {
        // 尝试使用系统配置的快捷键
        if let shortcut = getLaunchpadShortcut() {
            print("getLaunchpadShortcut", shortcut)
            simulateKeyPress(shortcut: shortcut)
            return
        }
        
        // 回退到默认的 Launchpad 键 (F4)
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw DesktopControlError.eventSourceCreationFailed
        }
        print("fallback to MacKeyCode.launchpad", MacKeyCode.launchpad.rawValue)
        simulateKeyPress(keyCode: MacKeyCode.launchpad.rawValue, source: source)
    }
    
    func moveToLeftSpace() throws {
        // 尝试使用系统配置的快捷键
        if let shortcut = getLeftSpaceShortcut() {
            print("getLeftSpaceShortcut", shortcut)
            simulateKeyPress(shortcut: shortcut)
            return
        }
        
        // 回退到默认快捷键 (Control + 左箭头)
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw DesktopControlError.eventSourceCreationFailed
        }
        print("fallback to MacKeyCode.leftArrow", MacKeyCode.leftArrow.rawValue)
        simulateKeyPress(keyCode: MacKeyCode.leftArrow.rawValue, flags: CGEventFlags.maskControl, source: source)
    }
    
    func moveToRightSpace() throws {
        // 尝试使用系统配置的快捷键
        if let shortcut = getRightSpaceShortcut() {
            print("getRightSpaceShortcut", shortcut)
            simulateKeyPress(shortcut: shortcut)
            return
        }
        
        // 回退到默认快捷键 (Control + 右箭头)
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw DesktopControlError.eventSourceCreationFailed
        }
        print("fallback to MacKeyCode.rightArrow", MacKeyCode.rightArrow.rawValue)
        simulateKeyPress(keyCode: MacKeyCode.rightArrow.rawValue, flags: CGEventFlags.maskControl, source: source)
    }
    
    // MARK: - Get Shortcut
    private func getSystemShortcut(for keyId: String) -> (keyCode: CGKeyCode, modifiers: CGEventFlags)? {
        guard let dict = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys")?["AppleSymbolicHotKeys"] as? [String: Any],
              let shortcutDict = dict[keyId] as? [String: Any],
              let enabled = shortcutDict["enabled"] as? Bool,
              enabled,
              let value = shortcutDict["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any],
              parameters.count >= 3,
              let keyCode = parameters[1] as? Int,
              let modifiers = parameters[2] as? Int else {
            return nil
        }
        
        // 转换修饰键
        var eventFlags: CGEventFlags = []
        if modifiers & 0x100000 != 0 { eventFlags.insert(.maskCommand) }
        if modifiers & 0x20000 != 0 { eventFlags.insert(.maskShift) }
        if modifiers & 0x40000 != 0 { eventFlags.insert(.maskControl) }
        if modifiers & 0x80000 != 0 { eventFlags.insert(.maskAlternate) }
        
        return (CGKeyCode(keyCode), eventFlags)
    }
    
    private func getMissionControlShortcut() -> (keyCode: CGKeyCode, modifiers: CGEventFlags)? {
        return getSystemShortcut(for: "32") // Mission Control 的快捷键 ID
    }
    
    private func getLaunchpadShortcut() -> (keyCode: CGKeyCode, modifiers: CGEventFlags)? {
        return getSystemShortcut(for: "160") // Launchpad 的快捷键 ID
    }
    
    private func getLeftSpaceShortcut() -> (keyCode: CGKeyCode, modifiers: CGEventFlags)? {
        return getSystemShortcut(for: "79") // 向左切换空间的快捷键 ID
    }
    
    private func getRightSpaceShortcut() -> (keyCode: CGKeyCode, modifiers: CGEventFlags)? {
        return getSystemShortcut(for: "81") // 向右切换空间的快捷键 ID
    }
    
    // MARK: - Simulate Key Press
    private func simulateKeyPress(shortcut: (keyCode: CGKeyCode, modifiers: CGEventFlags)) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        simulateKeyPress(keyCode: shortcut.keyCode, flags: shortcut.modifiers, source: source)
    }
    
    private func simulateKeyPress(keyCode: CGKeyCode, source: CGEventSource) {
        simulateKeyPress(keyCode: keyCode, flags: [], source: source)
    }
    
    private func simulateKeyPress(keyCode: UInt16, flags: CGEventFlags = [], source: CGEventSource) {
        do {
            try keyPost(keyCode: keyCode, flags: flags, source: source, keyDown: true)
            usleep(100000)
            try keyPost(keyCode: keyCode, flags: flags, source: source, keyDown: false)
        } catch {
            print("Create event error: \(error)")
        }
    }
    
    private func keyPost(keyCode: UInt16, flags: CGEventFlags = [], source: CGEventSource, keyDown: Bool) throws {
        // 创建事件
        guard let keyEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            throw DesktopControlError.eventSourceCreationFailed
        }
        // 为方向键添加必要的 flag
        let isArrowKey = [
            MacKeyCode.leftArrow.rawValue,
            MacKeyCode.rightArrow.rawValue,
            MacKeyCode.upArrow.rawValue,
            MacKeyCode.downArrow.rawValue
        ].contains(keyCode)
        var finalFlags = flags
        if isArrowKey {
            finalFlags.insert(.maskSecondaryFn)
            if flags.contains(.maskControl) {
                finalFlags.insert(.maskNonCoalesced)
            }
        }
        // 如果有 flag 才附加, 不然会有问题
        if !finalFlags.isEmpty {
            keyEvent.flags = finalFlags
        }
        // 发送事件
        keyEvent.post(tap: .cghidEventTap)
    }
}

// MARK: - Supporting Types
private enum MacKeyCode: CGKeyCode {
    case f3 = 0x3
    case f4 = 0x4
    case f3WithFnKey = 0x3F
    case missionControl = 0xA0
    case launchpad = 0x83      // F4 键的虚拟键码
    case leftArrow = 0x7B      // 123 in decimal
    case rightArrow = 0x7C     // 124 in decimal
    case upArrow = 0x7E        // 126 in decimal
    case downArrow = 0x7D      // 125 in decimal
}

// MARK: - Usage Example
extension DesktopControlManager {
    static func example() {
        do {
            // 触发 Mission Control
            try DesktopControlManager.shared.toggleMissionControl()
            
            // 触发 Launchpad
            try DesktopControlManager.shared.toggleLaunchpad()
            
            // 向左移动一个桌面空间
            try DesktopControlManager.shared.moveToLeftSpace()
            
            // 向右移动一个桌面空间
            try DesktopControlManager.shared.moveToRightSpace()
        } catch DesktopControlError.accessibilityNotAuthorized {
            print("需要辅助功能权限")
        } catch {
            print("操作失败: \(error)")
        }
    }
}
