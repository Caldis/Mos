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
        // 设置通知中心代理
        NSUserNotificationCenter.default.delegate = self
        // 禁止重复运行
        Utils.preventMultiRunning(killExist: true)
        // 读取用户设置
        Options.shared.readOptions()
        // 提示用户状态栏图标已隐藏
        Utils.notificateUserStatusBarIconIsHidden()
        // 监听用户切换, 在切换用户 session 时停止运行
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(AppDelegate.sessionDidActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(AppDelegate.sessionDidResign), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }
    // 运行后启动处理
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        ScrollCore.shared.startHandlingScroll()
    }
    // 关闭前停止处理
    func applicationWillTerminate(_ aNotification: Notification) {
        ScrollCore.shared.endHandlingScroll()
    }
    
    // 在切换用户时停止处理
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
