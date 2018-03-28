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
    
    // 禁止重复运行, 传入参数 kill 则杀掉已有进程, 否则自杀
    class func preventMultiRunning(killExist kill: Bool = false) {
        // 获取自己的 BundleId
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
    class func runForShowStatusItem () {
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
    private static var storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    class func instantiateControllerFromStoryboard<Controller>(withIdentifier identifier: String) -> Controller {
        let id = NSStoryboard.SceneIdentifier(rawValue: identifier)
        guard let controller = storyboard.instantiateController(withIdentifier: id) as? Controller else {
            fatalError("Can't find Controller: \(id)")
        }
        return controller
    }
    
}
