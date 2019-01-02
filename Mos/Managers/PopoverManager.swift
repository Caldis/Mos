//
//  PopoverManager.swift
//  Mos
//  管理气泡弹出面板
//  Created by Caldis on 2018/12/29.
//  Copyright © 2018 Caldis. All rights reserved.
//

import Cocoa

class PopoverManager {
    
    // 单例
    static let shared = PopoverManager()
    init() { print("Class 'PopoverManager' is initialized") }
    
    // 标识列表
    let identifier = (
        preferencesPopoverController: "PreferencesPopoverController"
    )
    // 引用列表
    var refs = [String: NSPopover]()
    
}

/**
 * 面板控制
 **/
extension PopoverManager {
    // 切换显示对应 Identifier 的气泡面板
    func togglePopover(withIdentifier identifier: String, relativeTo button: NSButton) {
        // 检查是否在引用列表中
        if let popover = refs[identifier] {
            // 切换显示
            if popover.isShown {
                hidePopover(withIdentifier: identifier)
            } else {
                showPopover(withIdentifier: identifier, relativeTo: button)
            }
        } else {
            showPopover(withIdentifier: identifier, relativeTo: button)
        }
    }
    // 显示对应 Identifier 的气泡面板
    func showPopover(withIdentifier identifier: String, relativeTo button: NSButton) {
        // 检查是否在引用列表中
        guard let popover = refs[identifier] else {
            // 如果不存在, 则从 Storyboard 获取一个实例并保存到引用列表中
            let popover = NSPopover()
            popover.contentViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier) as NSViewController
            refs[identifier] = popover
            // 重试
            showPopover(withIdentifier: identifier, relativeTo: button)
            return
        }
        // 显示
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        // 前置并激活
        NSApp.activate(ignoringOtherApps: true)
    }
    // 隐藏对应 Identifier 的气泡面板
    func hidePopover(withIdentifier identifier: String) {
        if let popover = refs[identifier] {
            // 隐藏
            popover.performClose(nil)
            // 销毁实例
            refs.removeValue(forKey: identifier)
        }
    }
}
