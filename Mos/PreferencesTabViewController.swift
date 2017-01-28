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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 实现tabViewDelegate
        tabView.delegate = self
        // 初始化当前的tabViewItem引用为第一个 (general)
        currentTabViewController = instantiateWindowController(with: "general") as! NSViewController
    }
    
    // 从StoryBroad获取一个实例
    func instantiateWindowController(with controllerIdentifier: String) -> Any {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        return storyboard.instantiateController(withIdentifier: controllerIdentifier)
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
        // 根据选中不同的窗口来改变Window高度, 先获取基本数据
        let nextIdentifier = tabViewItem?.identifier as! String
        let nextTabViewController = instantiateWindowController(with: nextIdentifier) as! NSViewController
        let preferencesWindow = (StatusMenuController.preferencesWindowController?.window)!
        let currentWindowRect = preferencesWindow.frame
        // 根据当前和现在的窗口高度差来计算新的窗口大小, 需要同时改变窗口PosY和Height
        let heightDiff = nextTabViewController.view.frame.height - currentTabViewController.view.frame.height
        let newWindowPosY = currentWindowRect.origin.y - heightDiff
        let newWindowHeight = currentWindowRect.height + heightDiff
        let generalSize = NSMakeRect(currentWindowRect.origin.x, newWindowPosY, currentWindowRect.width, newWindowHeight)
        preferencesWindow.setFrame(generalSize, display: true, animate: true)
        // 最后再更新当前的tabViewController引用
        currentTabViewController = instantiateWindowController(with: nextIdentifier) as! NSViewController
    }
}
