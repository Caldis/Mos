//
//  ButtonFilter.swift
//  Mos
//  鼠标按钮事件过滤器
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class ButtonFilter {
    
    // 单例
    static let shared = ButtonFilter()
    init() { NSLog("Module initialized: ButtonFilter") }
    
    // 过滤规则
    private var blockedApplications: Set<String> = []
    
    // MARK: - 事件过滤
    
    /// 过滤按钮事件
    /// - Parameter event: 输入的 CGEvent
    /// - Returns: 处理后的 CGEvent，如果为 nil 则表示事件被过滤掉
    func filterButtonEvent(_ event: CGEvent) -> CGEvent? {

        // 检查应用程序黑名单
        if isCurrentApplicationBlocked() {
            return nil
        }

        // 返回原始事件(目前不做修改)
        return event
    }
    
    /// 添加阻止的应用程序
    func addBlockedApplication(_ bundleIdentifier: String) {
        blockedApplications.insert(bundleIdentifier)
    }
    
    /// 移除阻止的应用程序
    func removeBlockedApplication(_ bundleIdentifier: String) {
        blockedApplications.remove(bundleIdentifier)
    }

    
    // MARK: - 辅助方法
    
    /// 检查当前应用程序是否在黑名单中
    private func isCurrentApplicationBlocked() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return blockedApplications.contains(bundleId)
    }

    /// 获取当前前台应用程序信息
    func getCurrentApplicationInfo() -> (name: String, bundleId: String)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return nil
        }
        
        let appName = frontmostApp.localizedName ?? "Unknown"
        return (name: appName, bundleId: bundleId)
    }
}
