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
        // 读取用户设置
        Options.shared.readOptions()
        // 禁止重复运行
        Utils.preventMultiRunning()
        // 监听用户切换, 切换用户时停止运行
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
    
}
