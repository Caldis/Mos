//
//  AppDelegate.swift
//  Mos
//
//  Created by Cb on 2017/1/10.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 禁止重复运行
        protectRunning()
        // 监听用户切换, 切换用户时停止运行
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(AppDelegate.sessionDidActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(AppDelegate.sessionDidResign), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        ScrollCore.startHandling()
    }
    func applicationWillTerminate(_ aNotification: Notification) {
         ScrollCore.endHandling()
    }
    
    // 在切换用户时停止处理
    @objc func sessionDidActive(notification:NSNotification){
         ScrollCore.startHandling()
    }
    @objc func sessionDidResign(notification:NSNotification){
         ScrollCore.endHandling()
    }
    
    // 禁止重复运行
    func protectRunning() {
        // App 标识符
        let mainBundleID = Bundle.main.bundleIdentifier!
        // 如果检测到在运行, 则自杀
        if NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).count > 1 {
            NSApp.terminate(nil)
        }
    }
}
