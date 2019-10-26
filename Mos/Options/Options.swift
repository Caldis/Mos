//
//  Options.swift
//  Mos
//  配置参数
//  Created by Caldis on 2018/2/19.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa
import LoginServiceKit
import ServiceManagement

class Options {
    
    // 单例
    static let shared = Options()
    init() { print("Class 'Options' is initialized") }
    
    // 读取锁, 防止冲突
    private var readingOptionsLock = false
    // JSON 编解码工具
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // 全局
    var global = OPTIONS_GLOBAL_DEFAULT()
    // 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT()
}

/**
 * 读取和写入
 **/
extension Options {
    
    // 从 UserDefaults 中读取到 currentOptions
    func readOptions() {
        // 配置项如果不存在则尝试用当前设置(默认设置)保存一次
        if UserDefaults.standard.object(forKey: "optionsExist") == nil { saveOptions() }
        // 锁定
        readingOptionsLock = true
        // 全局
        global.autoLaunch = LoginServiceKit.isExistLoginItems(at: Bundle.main.bundlePath)
        global.hideStatusItem = UserDefaults.standard.bool(forKey: "hideStatusItem")
        global.whitelist = UserDefaults.standard.bool(forKey: "whitelist")
        global.applications = EnhanceArray(
            withData: UserDefaults.standard.value(forKey: "applications") as! Data,
            matchKey: "bundleId",
            forObserver: Options.shared.saveOptions
        )
        // 滚动
        scroll.smooth = UserDefaults.standard.bool(forKey: "smooth")
        scroll.reverse = UserDefaults.standard.bool(forKey: "reverse")
        scroll.toggle = UserDefaults.standard.integer(forKey: "toggle")
        scroll.block = UserDefaults.standard.integer(forKey: "block")
        scroll.step = UserDefaults.standard.double(forKey: "step")
        scroll.speed = UserDefaults.standard.double(forKey: "speed")
        scroll.duration = UserDefaults.standard.double(forKey: "duration")
        scroll.durationTransition = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: scroll.duration)
        scroll.precision = UserDefaults.standard.double(forKey: "precision")
        // 解锁
        readingOptionsLock = false
    }
    
    // 写入到 UserDefaults
    func saveOptions() {
        if !readingOptionsLock {
            // 标识配置项存在
            UserDefaults.standard.set("optionsExist", forKey:"optionsExist")
            // 全局
            // UserDefaults.standard.set(options.autoLaunch, forKey:"autoLaunch") // 直接从系统值初始化
            UserDefaults.standard.set(global.hideStatusItem, forKey:"hideStatusItem")
            UserDefaults.standard.set(global.whitelist, forKey:"whitelist")
            UserDefaults.standard.set(global.applications.json(), forKey:"applications")
            // 滚动
            UserDefaults.standard.set(scroll.smooth, forKey:"smooth")
            UserDefaults.standard.set(scroll.reverse, forKey:"reverse")
            UserDefaults.standard.set(scroll.toggle, forKey:"toggle")
            UserDefaults.standard.set(scroll.block, forKey:"block")
            UserDefaults.standard.set(scroll.step, forKey:"step")
            UserDefaults.standard.set(scroll.speed, forKey:"speed")
            UserDefaults.standard.set(scroll.duration, forKey:"duration")
            UserDefaults.standard.set(scroll.precision, forKey:"precision")
        }
    }
}
