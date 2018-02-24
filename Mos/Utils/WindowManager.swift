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
    
    // 窗口标识
    let identifier = (
        monitorWindowController: "MonitorWindowController",
        preferencesWindowController: "PreferencesWindowController"
    )
    // 窗口引用
    var controller = [String: NSWindowController]()
    
    // 从 StoryBroad 获取一个 NSWindowController 的实例
    private var storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    private func getWindowControllerFromStoryboard(with identifier: String) -> NSWindowController {
        return storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: identifier)) as! NSWindowController
    }
    
    // 显示对应 Identifier 的窗口
    func showWindow(withIdentifier identifier: String, withTitle title:String) {
        // 判断窗口是否打开
        if controller[identifier] != nil {
            // 如果已经显示了, 就前置显示
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 如果没有显示, 则从 Storyboard 获取一个实例并保存到引用列表中
            let windowController = getWindowControllerFromStoryboard(with: identifier)
            controller[identifier] = getWindowControllerFromStoryboard(with: identifier)
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
