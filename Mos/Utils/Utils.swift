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
    
    // 禁止重复运行
    class func preventMultiRunning() {
        // 获取自己的 BundleId
        let mainBundleID = Bundle.main.bundleIdentifier!
        // 如果检测到在运行, 则自杀
        if NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).count > 1 {
            NSApp.terminate(nil)
        }
    }
    
    // 弹出提示框
    class func showAlert(title: String, description: String, alertStyle: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = description
        alert.alertStyle = alertStyle
        alert.addButton(withTitle: i18n.ensure)
        alert.runModal()
    }
    
}
