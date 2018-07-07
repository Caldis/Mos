//
//  Utils.swift
//  Mos
//  实用方法
//  Created by Caldis on 2017/3/24.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

// 实用方法
class Utils {
    
    // 装饰键
    static let modifierKeys = [
        59, // control
        58, // option
        55, // command
        56, // shiftLeft (60 is shiftRight)
    ]
    
    // 禁止重复运行
    // killExist = true 则杀掉已有进程, 否则自杀
    class func preventMultiRunning(killExist kill: Bool = false) {
        // 自己的 BundleId
        let mainBundleID = Bundle.main.bundleIdentifier!
        // 如果检测到在运行
        if NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).count > 1 {
            if kill {
                let runningInst = NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID)[0]
                runningInst.terminate()
            } else {
                NSApp.terminate(nil)
            }
        }
    }
    
    // 结束已有进程并尝试显示状态栏图标
    class func runForShowStatusItem() {
        // 获取自己的 BundleId
        let mainBundleID = Bundle.main.bundleIdentifier!
        // 如果检测到在运行, 则尝试结束进程, 并显示状态栏图标, 否则自杀
        if NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).count > 1  {
            let runningInst = NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID)[0]
            if runningInst.terminate() {
                Options.shared.others.hideStatusItem = false
            } else {
                NSApp.terminate(nil)
            }
        }
    }
    
    // 提示状态栏图标已隐藏
    class func notificateUserStatusBarIconIsHidden() {
        // 如果状态栏图标隐藏
        if Options.shared.others.hideStatusItem {
            // 定义通知
            let notification = NSUserNotification()
            notification.title = "Mos"
            notification.subtitle = i18n.mosIsRunningInThebackground
            notification.informativeText = i18n.mosStatusBarIconIsHidden
            notification.otherButtonTitle = i18n.gotIt
            notification.actionButtonTitle = i18n.showIt
            // 发送通知
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
    
    // 从 StoryBroad 获取一个特定 Controller 的实例
    private static let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    class func instantiateControllerFromStoryboard<Controller>(withIdentifier identifier: String) -> Controller {
        let id = NSStoryboard.SceneIdentifier(rawValue: identifier)
        guard let controller = storyboard.instantiateController(withIdentifier: id) as? Controller else {
            fatalError("Can't find Controller: \(id)")
        }
        return controller
    }
    
    // 辅助功能权限相关
    // 来源: http://see.sl088.com/wiki/Mac%E5%BC%80%E5%8F%91_%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90
    // 查询是否有辅助功能权限
    class func isHadAccessibilityPermissions() -> Bool{
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let privOptions = [trusted: false] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(privOptions)
        return accessEnabled
    }
    // 申请辅助功能权限
    class func requirePermissions() {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let privOptions = [trusted: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(privOptions)
        if !accessEnabled {
            AXIsProcessTrustedWithOptions(privOptions)
        }
    }
    
    // Dock 图标控制
    static var isDockIconVisible = false
    class func showDockIcon() {
        if !Utils.isDockIconVisible {
            NSApp.setActivationPolicy(NSApplication.ActivationPolicy.regular)
            isDockIconVisible = true
        }
    }
    class func hideDockIcon() {
        if WindowManager.shared.controller.count == 1 {
            NSApp.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
            isDockIconVisible = false
        }
    }
    class func toggleDockIcon() {
        if isDockIconVisible {
            hideDockIcon()
        } else {
            showDockIcon()
        }
    }
    
}
