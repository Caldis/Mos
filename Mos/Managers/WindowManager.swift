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
    init() { print("Class 'WindowManager' is a singleton, use the 'WindowManager.shared' to access it.") }
    
    // Storybroad 标识
    let identifier = (
        monitorWindowController: "MonitorWindowController",
        preferencesWindowController: "PreferencesWindowController",
        hideStatusItemWindowController: "HideStatusItemWindowController"
    )
    // 窗口引用列表
    var controller = [String: NSWindowController]()
    
    // 显示对应 Identifier 的窗口
    func showWindow(withIdentifier identifier: String, withTitle title:String) {
        // 判断窗口引用是否存在
        if let window = controller[identifier] {
            // 如果存在, 打开窗口并前置显示
            window.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 如果不存在, 则从 Storyboard 获取一个实例并保存到引用列表中
            let windowController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier) as NSWindowController
            controller[identifier] = windowController
            // 显示窗口
            windowController.window?.makeKeyAndOrderFront(self)
            windowController.window?.title = title
            windowController.showWindow(self)
            NSApp.activate(ignoringOtherApps: true)
        }
        // 显示 Dock 图标
        Utils.showDockIcon()
    }
    // 关闭对应 Identifier 的窗口
    func hideWindow(withIdentifier identifier: String) {
        // 隐藏 Dock 图标
        Utils.hideDockIcon()
        // 销毁窗口实例
        controller.removeValue(forKey: identifier)
    }
    
}
