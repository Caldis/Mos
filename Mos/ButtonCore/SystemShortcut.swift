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
}
