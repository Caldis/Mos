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
    init() { NSLog("Module initialized: Options") }
    
    // 读取锁, 防止冲突
    private var readingOptionsLock = false
    // JSON 编解码工具
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // 常规
    var general = OPTIONS_GENERAL_DEFAULT()
    // 滚动
    var scrollBasic = OPTIONS_SCROLL_BASIC_DEFAULT()
    var scrollAdvanced = OPTIONS_SCROLL_ADVANCED_DEFAULT() {
        didSet {Options.shared.saveOptions()}
    }
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
        // 常规
        general.autoLaunch = LoginServiceKit.isExistLoginItems(at: Bundle.main.bundlePath)
        general.hideStatusItem = UserDefaults.standard.bool(forKey: "hideStatusItem")
        general.whitelist = UserDefaults.standard.bool(forKey: "whitelist")
        general.applications = EnhanceArray(
            withData: UserDefaults.standard.value(forKey: "applications") as! Data,
            matchKey: "path",
            forObserver: Options.shared.saveOptions
        )
        // 滚动:基础
        scrollBasic.smooth = UserDefaults.standard.bool(forKey: "smooth")
        scrollBasic.reverse = UserDefaults.standard.bool(forKey: "reverse")
        // 滚动:高级
        scrollAdvanced.dash = UserDefaults.standard.integer(forKey: "dash")
        scrollAdvanced.toggle = UserDefaults.standard.integer(forKey: "toggle")
        scrollAdvanced.block = UserDefaults.standard.integer(forKey: "block")
        scrollAdvanced.step = UserDefaults.standard.double(forKey: "step")
        scrollAdvanced.speed = UserDefaults.standard.double(forKey: "speed")
        scrollAdvanced.duration = UserDefaults.standard.double(forKey: "duration")
        scrollAdvanced.durationTransition = OPTIONS_SCROLL_ADVANCED_DEFAULT.generateDurationTransition(with: scrollAdvanced.duration)
        scrollAdvanced.precision = UserDefaults.standard.double(forKey: "precision")
        // 解锁
        readingOptionsLock = false
        NSLog("Option readed")
    }
    
    // 写入到 UserDefaults
    func saveOptions() {
        if !readingOptionsLock {
            // 标识配置项存在
            UserDefaults.standard.set("optionsExist", forKey:"optionsExist")
            // 常规
            // UserDefaults.standard.set(options.autoLaunch, forKey:"autoLaunch") // 直接从系统值初始化
            UserDefaults.standard.set(general.hideStatusItem, forKey:"hideStatusItem")
            UserDefaults.standard.set(general.whitelist, forKey:"whitelist")
            UserDefaults.standard.set(general.applications.json(), forKey:"applications")
            // 滚动:基础
            UserDefaults.standard.set(scrollBasic.smooth, forKey:"smooth")
            UserDefaults.standard.set(scrollBasic.reverse, forKey:"reverse")
            // 滚动:高级
            UserDefaults.standard.set(scrollAdvanced.dash, forKey:"dash")
            UserDefaults.standard.set(scrollAdvanced.toggle, forKey:"toggle")
            UserDefaults.standard.set(scrollAdvanced.block, forKey:"block")
            UserDefaults.standard.set(scrollAdvanced.step, forKey:"step")
            UserDefaults.standard.set(scrollAdvanced.speed, forKey:"speed")
            UserDefaults.standard.set(scrollAdvanced.duration, forKey:"duration")
            UserDefaults.standard.set(scrollAdvanced.precision, forKey:"precision")
        }
    }
}
