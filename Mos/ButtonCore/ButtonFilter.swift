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
    private var enabledButtons: Set<ButtonType> = [.leftMouse, .rightMouse, .otherMouse]
    private var blockedApplications: Set<String> = []
    
    // 统计数据
    private var eventCount: [ButtonType: Int] = [:]
    private var lastEventTime: [ButtonType: Double] = [:]
    
    // MARK: - 事件过滤
    
    /// 过滤按钮事件
    /// - Parameter buttonEvent: 输入的按钮事件
    /// - Returns: 处理后的按钮事件，如果为 nil 则表示事件被过滤掉
    func filterButtonEvent(_ buttonEvent: ButtonEvent) -> ButtonEvent? {
        
        // 检查是否启用该类型按钮
        if !enabledButtons.contains(buttonEvent.eventData.buttonType) {
            return nil
        }
        
        // 检查应用程序黑名单
        if isCurrentApplicationBlocked() {
            return nil
        }
        
        // 更新统计数据
        updateStatistics(for: buttonEvent)
        
        // 记录事件到日志
        logButtonEvent(buttonEvent)
        
        // 返回原始事件(目前不做修改)
        return buttonEvent
    }
    
    // MARK: - 配置管理
    
    /// 启用特定类型的按钮监听
    func enableButton(_ buttonType: ButtonType) {
        enabledButtons.insert(buttonType)
        NSLog("ButtonFilter: Enabled \(buttonType.rawValue) button")
    }
    
    /// 禁用特定类型的按钮监听
    func disableButton(_ buttonType: ButtonType) {
        enabledButtons.remove(buttonType)
        NSLog("ButtonFilter: Disabled \(buttonType.rawValue) button")
    }
    
    /// 检查按钮类型是否启用
    func isButtonEnabled(_ buttonType: ButtonType) -> Bool {
        return enabledButtons.contains(buttonType)
    }
    
    /// 添加阻止的应用程序
    func addBlockedApplication(_ bundleIdentifier: String) {
        blockedApplications.insert(bundleIdentifier)
    }
    
    /// 移除阻止的应用程序
    func removeBlockedApplication(_ bundleIdentifier: String) {
        blockedApplications.remove(bundleIdentifier)
    }
    
    // MARK: - 统计功能
    
    /// 更新统计数据
    private func updateStatistics(for buttonEvent: ButtonEvent) {
        let buttonType = buttonEvent.eventData.buttonType
        let currentTime = buttonEvent.eventData.timestamp
        
        // 更新事件计数
        eventCount[buttonType, default: 0] += 1
        
        // 更新最后事件时间
        lastEventTime[buttonType] = currentTime
    }
    
    /// 获取按钮事件统计
    func getStatistics() -> [ButtonType: Int] {
        return eventCount
    }
    
    /// 重置统计数据
    func resetStatistics() {
        eventCount.removeAll()
        lastEventTime.removeAll()
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
    
    /// 记录按钮事件到日志
    private func logButtonEvent(_ buttonEvent: ButtonEvent) {
        let logMessage = "[\(buttonEvent.getFormattedTimestamp())] \(buttonEvent.getDescription())"
        NSLog("ButtonEvent: \(logMessage)")
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