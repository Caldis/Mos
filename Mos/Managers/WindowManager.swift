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
        preferencesWindowController: "PreferencesWindowController"
    )
    // 窗口引用列表
    var controller = [String: NSWindowController]()
    
    // 显示对应 Identifier 的窗口
    func showWindow(withIdentifier identifier: String, withTitle title:String) {
        // 判断窗口是否打开
        if controller[identifier] != nil {
            // 如果已经显示了, 就前置显示
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 如果没有显示, 则从 Storyboard 获取一个实例并保存到引用列表中
            let windowController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier) as NSWindowController
            controller[identifier] = windowController
            // 显示窗口
            windowController.window?.makeKeyAndOrderFront(self)
            windowController.window?.title = title
            windowController.showWindow(self)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    // 关闭对应 Identifier 的窗口
    func hideWindow(withIdentifier identifier: String) {
        controller[identifier] = nil
    }
    
}
