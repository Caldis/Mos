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
    
    // 引用列表
    var refs = [String: NSPopover]()
}

/**
 * 面板控制
 **/
extension PopoverManager {
    // 获取对应 Identifier 的气泡面板
    func get(withIdentifier identifier: String) -> NSPopover {
        // 检查是否在引用列表中
        if let popover = refs[identifier] {
            return popover
        } else {
            let popover = NSPopover()
            // 与该 Popover 区域外的元素交互时直接关闭窗口
            popover.behavior = NSPopover.Behavior.transient
            popover.contentViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier) as NSViewController
            refs[identifier] = popover
            return popover
        }
    }
    // 切换显示对应 Identifier 的气泡面板
    func togglePopover(withIdentifier identifier: String, relativeTo button: NSButton) {
        let popover = get(withIdentifier: identifier)
        if popover.isShown {
            hidePopover(withIdentifier: identifier)
        } else {
            showPopover(withIdentifier: identifier, relativeTo: button)
        }
    }
    // 显示对应 Identifier 的气泡面板
    func showPopover(withIdentifier identifier: String, relativeTo button: NSButton) {
        let popover = get(withIdentifier: identifier)
        // 显示
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
    }
    // 隐藏对应 Identifier 的气泡面板
    func hidePopover(withIdentifier identifier: String, destroy: Bool = false) {
        if let popover = refs[identifier] {
            // 隐藏 (若使用 performClose 则仅关闭当前, close 关闭所有)
            popover.close()
            // 销毁实例
            if destroy {
                refs.removeValue(forKey: identifier)
            }
        }
    }
}
