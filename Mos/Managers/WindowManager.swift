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
    init() { NSLog("Module initialized: WindowManager") }
    
    // 引用列表
    var refs = [String: NSWindowController]()
    
}

/**
 * 窗口控制
 **/
extension WindowManager {
    // 显示对应 Identifier 的窗口
    func showWindow(withIdentifier identifier: String, withTitle title: String? = nil) {
        // 检查是否在引用列表中
        guard let windowController = refs[identifier] else {
            // 如果不存在, 则从 Storyboard 获取一个实例并保存到引用列表中
            let windowController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier) as NSWindowController
            if let windowTitle = title {
                windowController.window?.title = windowTitle
            }
            refs[identifier] = windowController
            // 重试
            showWindow(withIdentifier: identifier, withTitle: title)
            return
        }
        // 取消显示 Dock 图标并激活 App，保留 accessory 模式避免切换 space
        // Utils.showDockIcon()
        NSApp.activate(ignoringOtherApps: true)
        
        // 显示并前置窗口
        windowController.showWindow(self)
        if let window = windowController.window {
            if window.isMiniaturized {
                window.deminiaturize(self)
            }
            window.makeKeyAndOrderFront(self)
            window.orderFrontRegardless()
        }
    }
    // 关闭对应 Identifier 的窗口
    func hideWindow(withIdentifier identifier: String, destroy: Bool = false) {
        // 隐藏 Dock 图标
        // Utils.hideDockIcon()
        // 销毁实例
        if destroy {
            refs.removeValue(forKey: identifier)
        }
    }
}
