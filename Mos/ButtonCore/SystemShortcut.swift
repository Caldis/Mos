//
//  SystemShortcut.swift
//  Mos
//
//  Created by 陈标 on 2025/8/28.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Foundation
import ApplicationServices

class SystemShortcut {
    // 系统快捷键映射常量
    enum ShortcutID: Int {
        case missionControl = 32        // Mission Control
        case missionControlSecondary = 34
        case desktopSwitchLeft = 79     // 切换到左侧桌面
        case desktopSwitchRight = 81    // 切换到右侧桌面
        case launchpad = 160            // Launchpad
        case showDesktop = 36           // 显示桌面
        case applicationWindows = 33    // 应用程序窗口
    }
    
    // 快捷键参数结构
    struct ShortcutParameters {
        let asciiCode: Int      // ASCII 码 (65535 表示无ASCII)
        let keyCode: Int        // 虚拟键码
        let modifiers: Int      // 修饰键
        let enabled: Bool       // 是否启用
        
        var isEmpty: Bool {
            return keyCode == 0 && modifiers == 0
        }
    }
    
    // 读取当前系统快捷键配置
    static func getCurrentShortcuts() -> [ShortcutID: ShortcutParameters] {
        var shortcuts: [ShortcutID: ShortcutParameters] = [:]
        
        // 读取 symbolichotkeys 配置
        guard let hotkeysPlist = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] else {
            print("无法读取系统快捷键配置")
            return shortcuts
        }
        
        // 解析每个快捷键
        for shortcut in [ShortcutID.missionControl, .desktopSwitchLeft,
                        .desktopSwitchRight, .launchpad, .showDesktop] {
            if let config = hotkeysPlist[String(shortcut.rawValue)] as? [String: Any],
               let value = config["value"] as? [String: Any],
               let parameters = value["parameters"] as? [Any],
               let enabled = config["enabled"] as? Bool,
               parameters.count >= 3 {
                
                let asciiCode = parameters[0] as? Int ?? 65535
                let keyCode = parameters[1] as? Int ?? 0
                let modifiers = parameters[2] as? Int ?? 0
                
                shortcuts[shortcut] = ShortcutParameters(
                    asciiCode: asciiCode,
                    keyCode: keyCode,
                    modifiers: modifiers,
                    enabled: enabled
                )
            }
        }
        
        return shortcuts
    }
    
    // 监控快捷键配置变更
    static func startMonitoring(callback: @escaping ([ShortcutID: ShortcutParameters]) -> Void) {
        let center = DistributedNotificationCenter.default()
        
        // 监听系统通知
        center.addObserver(
            forName: NSNotification.Name("com.apple.symbolichotkeys.changed"),
            object: nil,
            queue: nil
        ) { _ in
            DispatchQueue.global(qos: .utility).async {
                let newShortcuts = getCurrentShortcuts()
                DispatchQueue.main.async {
                    callback(newShortcuts)
                }
            }
        }
        
        // 使用 DispatchSource 监控文件变更（更简单和安全的方式）
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")
        
        let fileDescriptor = open(fileURL.path, O_EVTONLY)
        if fileDescriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: .write,
                queue: DispatchQueue.global(qos: .utility)
            )
            
            source.setEventHandler {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let shortcuts = getCurrentShortcuts()
                    callback(shortcuts)
                }
            }
            
            source.setCancelHandler {
                close(fileDescriptor)
            }
            
            source.resume()
        }
    }
}
