//
//  WindowManager.swift
//  Mos
//  管理窗口创建及初始化
//  Created by Caldis on 2018/2/24.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class WindowManager {
    
    // 单例
    static let shared = WindowManager()
    init() { print("Class 'WindowManager' is initialized") }
    
    // 标识列表
    let identifier = (
        welcomeWindowController: "WelcomeWindowController",
        monitorWindowController: "MonitorWindowController",
        preferencesWindowController: "PreferencesWindowController",
        hideStatusItemWindowController: "HideStatusItemWindowController"
    )
    // 引用列表
    var refs = [String: NSWindowController]()
    
}

/**
 * 窗口控制
 **/
extension WindowManager {
    // 显示对应 Identifier 的窗口
    func showWindow(withIdentifier identifier: String, withTitle title: String) {
        // 检查是否在引用列表中
        guard let windowController = refs[identifier] else {
            // 如果不存在, 则从 Storyboard 获取一个实例并保存到引用列表中
            let windowController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier) as NSWindowController
            windowController.window?.title = title
            refs[identifier] = windowController
            // 重试
            showWindow(withIdentifier: identifier, withTitle: title)
            return
        }
        // 显示
        windowController.showWindow(self)
        // 前置并激活
        windowController.window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
        // 显示 Dock 图标
        Utils.showDockIcon()
    }
    // 关闭对应 Identifier 的窗口
    func hideWindow(withIdentifier identifier: String) {
        // 隐藏 Dock 图标
        Utils.hideDockIcon()
        // 销毁实例
        // refs.removeValue(forKey: identifier)
    }
}
