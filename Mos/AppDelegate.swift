//
//  AppDelegate.swift
//  Mos
//
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {

    // 运行前预处理
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Dev 清空用户设置
        // UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        // 设置通知中心代理
        NSUserNotificationCenter.default.delegate = self
        // 禁止重复运行
        Utils.preventMultiRunning(killExist: true)
        // 读取用户设置
        Options.shared.readOptions()
        // 提示用户状态栏图标已隐藏
        Utils.notificateUserStatusBarIconIsHidden()
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
    // 关闭前停止滚动处理
    func applicationWillTerminate(_ aNotification: Notification) {
        ScrollCore.shared.endHandlingScroll()
    }
    
    // 检查是否有访问 accessibility 权限, 如果有则启动滚动处理, 并结束计时器
    // 10.14(Mojave) 后, 若无该权限会直接在创建 eventTap 时报错 (https://developer.apple.com/videos/play/wwdc2018/702/)
    @objc func startWithAccessibilityPermissionsChecker(_ timer: Timer?) {
        if let checkTimer = timer {
            if Utils.isHadAccessibilityPermissions() {
                checkTimer.invalidate()
                ScrollCore.shared.startHandlingScroll()
            }
        } else {
            if Utils.isHadAccessibilityPermissions() {
                ScrollCore.shared.startHandlingScroll()
            } else {
                // 如果应用不在辅助权限列表内, 则弹出欢迎窗口
                WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.welcomeWindowController, withTitle: "")
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
    @objc func sessionDidActive(notification:NSNotification){
         ScrollCore.shared.startHandlingScroll()
    }
    @objc func sessionDidResign(notification:NSNotification){
         ScrollCore.shared.endHandlingScroll()
    }
    
    // 收到通知后显示图标
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        Options.shared.others.hideStatusItem = false
    }
    
}
