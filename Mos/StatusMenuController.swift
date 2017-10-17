//
//  StatusBarController.swift
//  Mos
//
//  Created by Cb on 2017/1/15.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class StatusMenuController: NSObject {
    
    // 国际化相关
    let ScrollMonitorWindowTitle = NSLocalizedString("Scroll Monitor", comment: "")
    let PreferencesWindowTitle = NSLocalizedString("Preferences", comment: "")
    
    // 创建窗口相关
    static var scrollMonitorWindowIsOpen = false
    static var preferencesWindowIsOpen = false
    static var scrollMonitorWindowController:NSWindowController?
    static var preferencesWindowController:NSWindowController?
    
    // 状态栏相关
    @IBOutlet weak var statusMenu: NSMenu!
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    override func awakeFromNib() {
        // 初始化状态栏
        let statusBarIcon = #imageLiteral(resourceName: "StatusBarIcon")
        statusBarIcon.isTemplate = true
        statusItem.image = statusBarIcon
        statusItem.menu = statusMenu
    }
    
    // 从StoryBroad获取一个实例
    func instantiateWindowController(with controllerIdentifier: String) -> Any {
        let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
        return storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: controllerIdentifier))
    }
    
    // 显示窗口
    func showWindowWithTitle(_ controller:NSWindowController, title:String) {
        controller.window?.title = title
        controller.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // 点击ScrollWatcher按钮
    @IBAction func scrollWatcherClick(_ sender: Any) {
        // 判断窗口是否打开
        if StatusMenuController.scrollMonitorWindowIsOpen {
            // 如果已经显示了, 就前置显示
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 如果没有显示, 则从 StoryBroad 获取一个实例
            StatusMenuController.scrollMonitorWindowController = instantiateWindowController(with: "ScrollMonitorWindowController") as? ScrollMonitorWindowController
            StatusMenuController.scrollMonitorWindowController?.window?.makeKeyAndOrderFront(self)
            showWindowWithTitle(StatusMenuController.scrollMonitorWindowController!, title: ScrollMonitorWindowTitle)
            StatusMenuController.scrollMonitorWindowIsOpen = true
        }
    }
    
    // 点击Preferences按钮
    @IBAction func preferencesClick(_ sender: Any) {
        // 判断窗口是否打开
        if StatusMenuController.preferencesWindowIsOpen {
            // 如果已经显示了, 就前置显示
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 如果没有显示, 则从 StoryBroad 获取一个实例
            StatusMenuController.preferencesWindowController = instantiateWindowController(with: "PreferencesWindowController") as? PreferencesWindowController
            StatusMenuController.preferencesWindowController?.window?.makeKeyAndOrderFront(self)
            showWindowWithTitle(StatusMenuController.preferencesWindowController!, title: PreferencesWindowTitle)
            StatusMenuController.preferencesWindowIsOpen = true
        }
    }
    
    // 点击退出按钮
    @IBAction func quitButtonClick(_ sender: Any) {
        // 终止程序
        NSApplication.shared.terminate(self)
    }
}
