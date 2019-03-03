//
//  PreferencesTabViewController.swift
//  Mos
//  偏好设置的 TabController 容器
//  Created by Caldis on 2017/1/20.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesTabViewController: NSTabViewController {
    
    // 界面 TabViewController 引用
    var currentTabViewController: NSViewController?
    // 容器: Window
    var currentWindow: NSWindowController?
    
    override func viewWillAppear() {
        // 初始化 TabViewController 引用
        if let currentTabViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: "general") as NSViewController? {
            // 初始化引用
            self.currentTabViewController = currentTabViewController
            // Window: 初始化容器引用
            if let currentWindow = WindowManager.shared.refs[WindowManager.shared.identifier.preferencesWindowController] {
                // 初始化引用
                self.currentWindow = currentWindow
                // 初始化窗口大小
                let currentWindowRect = currentWindow.window!.frame
                let generalSize = NSMakeRect(currentWindowRect.origin.x, currentWindowRect.origin.y, 450, 265)
                currentWindow.window!.setFrame(generalSize, display: true, animate: true)
            }
        }
    }
    
    override func viewWillDisappear() {
        currentTabViewController = nil
        currentWindow = nil
    }
    
}

/**
 * TabViews 事件
 **/
extension PreferencesTabViewController {
    // 点击 TabView 按钮响应
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        if let currentTabViewController = self.currentTabViewController {
            // Window: 动态设置容器窗口大小/高度
            if let currentWindow = WindowManager.shared.refs[WindowManager.shared.identifier.preferencesWindowController] {
                // 根据目标 View 的尺寸来改变 Window 高度
                let targetTabViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: tabViewItem!.identifier as! String) as NSViewController
                let currentWindowFrame = currentWindow.window!.frame
                // 根据 View 的尺寸差计算大小, 同时移动窗口 PosY 和 Height 保持窗口基于左上角定位不变
                let heightDiff = targetTabViewController.view.frame.height - currentTabViewController.view.frame.height
                let targetWindowPosY = currentWindowFrame.origin.y - heightDiff
                let targetWindowHeight = currentWindowFrame.height + heightDiff
                let targetWindowSize = NSMakeRect(currentWindowFrame.origin.x, targetWindowPosY, currentWindowFrame.width, targetWindowHeight)
                currentWindow.window!.setFrame(targetWindowSize, display: true, animate: true)
                // 更新当前的 tabViewController 引用
                self.currentTabViewController = targetTabViewController
            }
        }
    }
}
