//
//  AppDelegate.swift
//  Mos
//
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    // 运行前预处理
    func applicationWillFinishLaunching(_ notification: Notification) {
        // DEBUG
        // 清空用户设置
        // UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        // 直接弹出设置窗口
        // WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        
        // 开始
        // 禁止重复运行
        Utils.preventMultiRunning(killExist: true)
        // 读取用户设置
        Options.shared.readOptions()
        // 监听用户切换, 在切换用户 session 时停止运行
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidResign),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
    }
    // 运行后启动滚动处理
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        startWithAccessibilityPermissionsChecker(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return true
        }
        if Utils.isHadAccessibilityPermissions() {
            WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        }
        return false
    }
    // 关闭前停止滚动处理
    func applicationWillTerminate(_ aNotification: Notification) {
        ScrollCore.shared.endHandlingScroll()
        NSLog("ScrollCore End: Terminate")
    }
    
    // 检查是否有访问 accessibility 权限, 如果有则启动滚动处理, 并结束计时器
    // 10.14(Mojave) 后, 若无该权限会直接在创建 eventTap 时报错 (https://developer.apple.com/videos/play/wwdc2018/702/)
    @objc func startWithAccessibilityPermissionsChecker(_ timer: Timer?) {
        NSLog("Checking Accessibility")
        if let validTimer = timer {
            // 开启辅助权限后, 关闭定时器, 开始处理
            if Utils.isHadAccessibilityPermissions() {
                validTimer.invalidate()
                ScrollCore.shared.startHandlingScroll()
                NSLog("ScrollCore Start: First Open (Accessibility Enabled)")
            }
        } else {
            if Utils.isHadAccessibilityPermissions() {
                ScrollCore.shared.startHandlingScroll()
                NSLog("ScrollCore Start: Normal Open")
            } else {
                // 如果应用不在辅助权限列表内, 则弹出欢迎窗口
                WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
                // 启动定时器检测权限, 当拥有授权时启动滚动处理
                Timer.scheduledTimer(
                    timeInterval: 2.0,
                    target: self,
                    selector: #selector(startWithAccessibilityPermissionsChecker(_:)),
                    userInfo: nil,
                    repeats: true
                )
            }
        }
    }
    
    // 在切换用户时停止滚动处理
    @objc func sessionDidActive(notification: NSNotification){
        ScrollCore.shared.startHandlingScroll()
        NSLog("ScrollCore Start: Session Active")
    }
    @objc func sessionDidResign(notification: NSNotification){
        ScrollCore.shared.endHandlingScroll()
        NSLog("ScrollCore End: Session Resign")
    }
}
