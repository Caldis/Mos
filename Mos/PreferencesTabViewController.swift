//
//  PreferencesTabViewController.swift
//  Mos
//
//  Created by Cb on 2017/1/20.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class PreferencesTabViewController: NSTabViewController {
    
    // 初始的tabViewController引用
    var currentTabViewController:NSViewController!
    // 容器窗口引用
    var preferencesWindowRef:NSWindow!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 实现tabViewDelegate (XCode9改动, 不需要重新声明 delegate https://developer.apple.com/library/content/releasenotes/AppKit/RN-AppKit/index.html)
        // tabView.delegate = self
    }
    override func viewWillAppear() {
        // 更新当前的容器窗口引用
        preferencesWindowRef = StatusMenuController.preferencesWindowController!.window!
        // 更新当前的tabViewController引用
        currentTabViewController = instantiateWindowController(with: "general") as! NSViewController
        // 初次打开, 初始化窗口大小 (只能写死, 蠢方法, 不知道为什么 10.13 下初始大小会变成 500)
        let currentWindowRect = preferencesWindowRef.frame
        let generalSize = NSMakeRect(currentWindowRect.origin.x, currentWindowRect.origin.y, 450, 260)
        preferencesWindowRef.setFrame(generalSize, display: true, animate: true)
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
    
    // 点击Tabview上的toolbar类型按钮时动态设置窗口大小/高度
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        // 切换 Tab, 根据选中不同的窗口来改变Window高度, 先获取基本数据
        // 避免第一次调用
        if currentTabViewController !== nil {
            let nextIdentifier = tabViewItem?.identifier as! String
            let nextTabViewController = instantiateWindowController(with: nextIdentifier) as! NSViewController
            let currentWindowRect = preferencesWindowRef.frame
            // 根据当前和现在的窗口高度差来计算新的窗口大小, 且需要同时移动窗口PosY和Height保持窗口位置不变
            let heightDiff = nextTabViewController.view.frame.height - currentTabViewController.view.frame.height
            let newWindowPosY = currentWindowRect.origin.y - heightDiff
            let newWindowHeight = currentWindowRect.height + heightDiff
            let generalSize = NSMakeRect(currentWindowRect.origin.x, newWindowPosY, currentWindowRect.width, newWindowHeight)
            preferencesWindowRef.setFrame(generalSize, display: true, animate: true)
            // 更新当前的tabViewController引用
            currentTabViewController = nextTabViewController
        }
    }
}
