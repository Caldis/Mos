//
//  Options.swift
//  Mos
//  配置参数
//  Created by Caldis on 2018/2/19.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Options {
    
    // 单例
    static let shared = Options()
    init() { print("Class 'Options' is a singleton, use the 'Options.shared' to access it.") }
    
    // 默认设置
    static let DEFAULT_OPTIONS = (
        // 基础
        basic: ( smooth: true, reverse: true, autoLaunch: false ),
        // 高级
        advanced: ( speed: 4.0, transition: 0.14 ),
        // 例外
        exception: ( whitelist: false, applications: [ExceptionalApplication](), applicationsDict: [String: ExceptionalApplication]() )
    )
    // 当前设置
    var current = DEFAULT_OPTIONS {
        // 更改后
        didSet {
            // 更新 applicationsDict
            if(oldValue.exception.applications.count != current.exception.applications.count) {
                current.exception.applicationsDict = generateApplicationsDict()
            }
            // 自动保存到 UserDefaults
            saveOptions()
        }
    }
    
    // 读取锁, 防止冲突
    private var readingOptionsLock = false
    // JSON 编解码工具
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // 从 UserDefaults 中读取到 currentOptions
    func readOptions() {
        readingOptionsLock = true
        // 配置项如果不存在则尝试用当前设置(默认设置)保存一次
        if UserDefaults.standard.object(forKey: "optionsExist") == nil { saveOptions() }
        // 基础
        current.basic.smooth = UserDefaults.standard.bool(forKey: "smooth")
        current.basic.reverse = UserDefaults.standard.bool(forKey: "reverse")
        current.basic.autoLaunch = UserDefaults.standard.bool(forKey: "autoLaunch")
        // 高级
        current.advanced.speed = UserDefaults.standard.double(forKey: "speed")
        current.advanced.transition = UserDefaults.standard.double(forKey: "transition")
        // 例外
        current.exception.whitelist = UserDefaults.standard.bool(forKey: "whitelist")
        current.exception.applications = try! decoder.decode(Array.self, from: UserDefaults.standard.value(forKey: "applications") as! Data) as [ExceptionalApplication]
        current.exception.applicationsDict = generateApplicationsDict()
        readingOptionsLock = false
    }
    
    // 写入到 UserDefaults
    func saveOptions() {
        if !readingOptionsLock {
            // 标识配置项存在
            UserDefaults.standard.set("optionsExist", forKey:"optionsExist")
            // 基础
            UserDefaults.standard.set(current.basic.smooth, forKey:"smooth")
            UserDefaults.standard.set(current.basic.reverse, forKey:"reverse")
            UserDefaults.standard.set(current.basic.autoLaunch, forKey:"autoLaunch")
            // 高级
            UserDefaults.standard.set(current.advanced.speed, forKey:"speed")
            UserDefaults.standard.set(current.advanced.transition, forKey:"transition")
            // 例外
            UserDefaults.standard.set(current.exception.whitelist, forKey:"whitelist")
            UserDefaults.standard.set(try! encoder.encode(current.exception.applications), forKey: "applications")
        }
    }
    
    // 生成 applicationsDict 对象, 用于快速查找
    private func generateApplicationsDict() -> [String: ExceptionalApplication] {
        var applicationsDict = [String: ExceptionalApplication]()
        current.exception.applications.forEach { (application) in
            applicationsDict[application.bundleId] = application
        }
        return applicationsDict
    }
    
}
