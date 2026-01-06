//
//  ButtonUtils.swift
//  Mos
//  按钮绑定工具类 - 获取配置和管理绑定
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class ButtonUtils {

    // 单例
    static let shared = ButtonUtils()
    init() {}

    // MARK: - 获取按钮绑定配置

    /// 获取当前应用的按钮绑定配置
    /// - Returns: 按钮绑定列表 (只返回对当前应用生效的绑定)
    func getButtonBindings() -> [ButtonBinding] {
        // 获取当前前台应用的路径
        let currentAppPath = getCurrentApplicationPath()
        
        // 过滤出对当前应用生效的绑定
        return Options.shared.buttons.binding.filter { binding in
            binding.isActiveForApplication(currentAppPath)
        }
    }
    
    /// 获取所有按钮绑定 (不过滤)
    /// - Returns: 所有按钮绑定列表
    func getAllButtonBindings() -> [ButtonBinding] {
        return Options.shared.buttons.binding
    }

    // MARK: - 分应用支持

    /// 获取当前前台应用的路径
    /// - Returns: 应用路径 (优先返回 executablePath, 其次 bundlePath)
    private func getCurrentApplicationPath() -> String? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        // 优先使用 executableURL, 与 Application 模型保持一致
        if let executablePath = frontmostApp.executableURL?.path {
            return executablePath
        }
        
        // 备选使用 bundleURL
        if let bundlePath = frontmostApp.bundleURL?.path {
            return bundlePath
        }
        
        return nil
    }
    
    /// 获取当前前台应用信息
    /// - Returns: (名称, 路径) 元组, 如果无法获取返回 nil
    func getCurrentApplicationInfo() -> (name: String, path: String)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let name = frontmostApp.localizedName ?? "Unknown"
        
        // 优先使用 executableURL
        if let path = frontmostApp.executableURL?.path {
            return (name: name, path: path)
        }
        
        // 备选使用 bundleURL
        if let path = frontmostApp.bundleURL?.path {
            return (name: name, path: path)
        }
        
        return nil
    }
}
