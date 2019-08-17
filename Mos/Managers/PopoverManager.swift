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
//    var monitors = [EventMonitor]()
//    var identifiers = [String]()
//
//    // 点击拦截
//    func clickEventCallBack(_:NSEvent?) {
//        PopoverManager.shared.hidePopover(withIdentifier: identifiers.last!)
//    }
//
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
        // 添加外部点击监听
//        monitors.last?.stop()
//        monitors.append(EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: clickEventCallBack))
//        identifiers.append(identifier)
    }
    // 隐藏对应 Identifier 的气泡面板
    func hidePopover(withIdentifier identifier: String, destroy: Bool = false) {
        if let popover = refs[identifier] {
            // 隐藏
            popover.performClose(nil)
            // 停止当前, 删除并启用上一个监听
//            monitors.popLast()?.stop()
//            _ = identifiers.popLast()
//            monitors.last?.start()
            // 销毁实例
            if destroy {
                refs.removeValue(forKey: identifier)
            }
        }
    }
}
