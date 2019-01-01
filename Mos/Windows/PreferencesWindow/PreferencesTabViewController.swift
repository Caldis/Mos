//
//  PreferencesTabViewController.swift
//  Mos
//  偏好设置面板容器 Tab
//  Created by Caldis on 2017/1/20.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesTabViewController: NSTabViewController {
    
    // 界面 Controller 引用相关
    var currentWindowController: NSWindowController?
    var currentTabViewController: NSViewController?
    
    override func viewWillAppear() {
        // 初始化 Controller 引用
        currentWindowController = WindowManager.shared.controllers[WindowManager.shared.identifier.preferencesWindowController]!
        currentTabViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: "general") as NSViewController
        // 初始化窗口大小
        let currentWindowRect = currentWindowController!.window!.frame
        let generalSize = NSMakeRect(currentWindowRect.origin.x, currentWindowRect.origin.y, 450, 265)
        currentWindowController!.window!.setFrame(generalSize, display: true, animate: true)
    }
    
    override func viewWillDisappear() {
        currentWindowController = nil
        currentTabViewController = nil
    }
    
    // 点击 Tabview 上的 toolbar 类型按钮时动态设置窗口大小/高度
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        if currentTabViewController != nil {
            // 切换 Tab, 根据选中不同的窗口来改变 Window 高度
            let nextTabViewControllerIdentifier = tabViewItem!.identifier as! String
            let nextTabViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: nextTabViewControllerIdentifier) as NSViewController
            let currentWindowRect = currentWindowController!.window!.frame
            // 根据 View 的尺寸差计算大小 (同时移动窗口 PosY 和 Height 保持窗口基于左上角定位不变)
            let heightDiff = nextTabViewController.view.frame.height - currentTabViewController!.view.frame.height
            let nextWindowPosY = currentWindowRect.origin.y - heightDiff
            let nextWindowHeight = currentWindowRect.height + heightDiff
            let nextWindowSize = NSMakeRect(currentWindowRect.origin.x, nextWindowPosY, currentWindowRect.width, nextWindowHeight)
            currentWindowController!.window!.setFrame(nextWindowSize, display: true, animate: true)
            // 更新当前的 tabViewController 引用
            currentTabViewController = nextTabViewController
        }
    }
    
}
