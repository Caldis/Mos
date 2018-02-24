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
    var currentTabViewController: NSViewController!
    var currentWindowController: NSWindow!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    override func viewWillAppear() {
        // 当前的容器窗口引用
        currentWindowController = WindowManager.shared.controller[WindowManager.shared.identifier.preferencesWindowController]!.window
        // 更新当前的 tabViewController 引用
        currentTabViewController = instantiateWindowController(with: "general") as! NSViewController
        // 初次打开, 初始化窗口大小 (只能写死, 蠢方法, 不知道为什么 10.13 下初始大小会变成 500)
        let currentWindowRect = currentWindowController.frame
        let generalSize = NSMakeRect(currentWindowRect.origin.x, currentWindowRect.origin.y, 450, 260)
        currentWindowController.setFrame(generalSize, display: true, animate: true)
    }
    
    // 从StoryBroad获取一个实例
    func instantiateWindowController(with controllerIdentifier: String) -> Any {
        let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
        return storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: controllerIdentifier))
    }
    // 从tabViewController中获取一个指定id的item
    func tabViewItemInTabViewController(identifier: String) -> NSTabViewItem? {
        let tabViewController = instantiateWindowController(with: "preferencesTabViewController") as! NSTabViewController
        // 遍历数组查找对应项
        if let tabViewItem = tabViewController.tabViewItems.filter({($0.identifier as! String) == identifier}).first {
            return tabViewItem
        } else {
            return nil
        }
    }
    
    // 点击 Tabview 上的 toolbar 类型按钮时动态设置窗口大小/高度
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        // 切换 Tab, 根据选中不同的窗口来改变 Window 高度, 先获取基本数据
        // 避免第一次调用
        if currentTabViewController !== nil {
            let nextIdentifier = tabViewItem?.identifier as! String
            let nextTabViewController = instantiateWindowController(with: nextIdentifier) as! NSViewController
            let currentWindowRect = currentWindowController.frame
            // 根据当前和现在的窗口高度差来计算新的窗口大小, 且需要同时移动窗口 PosY 和 Height 保持窗口位置不变
            let heightDiff = nextTabViewController.view.frame.height - currentTabViewController.view.frame.height
            let newWindowPosY = currentWindowRect.origin.y - heightDiff
            let newWindowHeight = currentWindowRect.height + heightDiff
            let generalSize = NSMakeRect(currentWindowRect.origin.x, newWindowPosY, currentWindowRect.width, newWindowHeight)
            currentWindowController.setFrame(generalSize, display: true, animate: true)
            // 更新当前的 tabViewController 引用
            currentTabViewController = nextTabViewController
        }
    }
}
