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
    /// - Returns: 按钮绑定列表
    func getButtonBindings() -> [ButtonBinding] {
        // 预留: 未来支持分应用配置
        // if let app = getTargetApplication(),
        //    let appBindings = app.buttons?.binding {
        //     return appBindings
        // }

        // 使用全局配置
        return Options.shared.buttons.binding
    }

    // MARK: - 分应用支持 (预留接口)

    /// 获取当前焦点应用的配置对象 (预留)
    /// - Returns: Application 对象或 nil
    private func getTargetApplication() -> Application? {
        // 预留: 未来实现类似 ScrollUtils.getTargetApplication 的逻辑
        // let runningApp = NSWorkspace.shared.frontmostApplication
        // return Options.shared.application.applications.first { $0.bundleId == runningApp?.bundleIdentifier }
        return nil
    }
}
