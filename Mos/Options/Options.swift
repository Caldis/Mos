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

struct OptionItem {
    struct General {
        static let OptionsExist = "optionsExist"
        static let HideStatusItem = "hideStatusItem"
    }
    
    struct Scroll {
        static let Smooth = "smooth"
        static let Reverse = "reverse"
        static let Dash = "dash"
        static let Toggle = "toggle"
        static let Block = "block"
        static let Step = "step"
        static let Speed = "speed"
        static let Duration = "duration"
        static let Precision = "precision"
    }
    
    struct Application {
        static let Allowlist = "allowlist"
        static let Applications = "applications"
    }
}

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
    var scroll = OPTIONS_SCROLL_DEFAULT() {
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
        if UserDefaults.standard.object(forKey: OptionItem.General.OptionsExist) == nil { saveOptions() }
        // 锁定
        readingOptionsLock = true
        // 常规
        general.autoLaunch = LoginServiceKit.isExistLoginItems(at: Bundle.main.bundlePath)
        general.hideStatusItem = UserDefaults.standard.bool(forKey: OptionItem.General.HideStatusItem)
        // 滚动
        scroll.smooth = UserDefaults.standard.bool(forKey: OptionItem.Scroll.Smooth)
        scroll.reverse = UserDefaults.standard.bool(forKey: OptionItem.Scroll.Reverse)
        scroll.dash = UserDefaults.standard.integer(forKey: OptionItem.Scroll.Dash)
        scroll.toggle = UserDefaults.standard.integer(forKey: OptionItem.Scroll.Toggle)
        scroll.block = UserDefaults.standard.integer(forKey: OptionItem.Scroll.Block)
        scroll.step = UserDefaults.standard.double(forKey: OptionItem.Scroll.Step)
        scroll.speed = UserDefaults.standard.double(forKey: OptionItem.Scroll.Speed)
        scroll.duration = UserDefaults.standard.double(forKey: OptionItem.Scroll.Duration)
        scroll.durationTransition = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: scroll.duration)
        scroll.precision = UserDefaults.standard.double(forKey: OptionItem.Scroll.Precision)
        // 应用
        general.allowlist = UserDefaults.standard.bool(forKey: OptionItem.Application.Allowlist)
        general.applications = EnhanceArray(
            withData: UserDefaults.standard.value(forKey: OptionItem.Application.Applications) as! Data,
            matchKey: "path",
            forObserver: Options.shared.saveOptions
        )
        // 解锁
        readingOptionsLock = false
    }
    
    // 写入到 UserDefaults
    func saveOptions() {
        if !readingOptionsLock {
            // 标识配置项存在
            UserDefaults.standard.set("optionsExist", forKey: OptionItem.General.OptionsExist)
            // 常规
            UserDefaults.standard.set(general.hideStatusItem, forKey: OptionItem.General.HideStatusItem)
            // 滚动
            UserDefaults.standard.set(scroll.smooth, forKey: OptionItem.Scroll.Smooth)
            UserDefaults.standard.set(scroll.reverse, forKey: OptionItem.Scroll.Reverse)
            UserDefaults.standard.set(scroll.dash, forKey: OptionItem.Scroll.Dash)
            UserDefaults.standard.set(scroll.toggle, forKey: OptionItem.Scroll.Toggle)
            UserDefaults.standard.set(scroll.block, forKey: OptionItem.Scroll.Block)
            UserDefaults.standard.set(scroll.step, forKey: OptionItem.Scroll.Step)
            UserDefaults.standard.set(scroll.speed, forKey: OptionItem.Scroll.Speed)
            UserDefaults.standard.set(scroll.duration, forKey: OptionItem.Scroll.Duration)
            UserDefaults.standard.set(scroll.precision, forKey: OptionItem.Scroll.Precision)
            // 应用
            UserDefaults.standard.set(general.allowlist, forKey: OptionItem.Application.Allowlist)
            UserDefaults.standard.set(general.applications.json(), forKey: OptionItem.Application.Applications)
        }
    }
}
