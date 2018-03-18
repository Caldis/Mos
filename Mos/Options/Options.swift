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
        basic: (
            smooth: true,
            reverse: true,
            autoLaunch: false
        ),
        // 高级
        advanced: (
            step: 25.0,
            speed: 3.00,
            duration: 4.30, durationTransition: 0.17,
            precision: 1.00
        ),
        // 例外
        exception: (
            whitelist: false,
            applications: [ExceptionalApplication](), applicationsDict: [String: ExceptionalApplication]()
        )
    )
    // 当前设置
    var basic = DEFAULT_OPTIONS.basic {
        didSet {
            // 设置自启
            if(oldValue.autoLaunch != basic.autoLaunch) {
                if basic.autoLaunch {
                    LaunchStarter.enableLaunchAtStartup()
                } else {
                    LaunchStarter.disableLaunchAtStartup()
                }
            }
            // 保存到 UserDefaults
            saveOptions()
        }
    }
    var advanced = DEFAULT_OPTIONS.advanced {
        didSet {
            // 更新 durationTransition
            if(oldValue.duration != advanced.duration) {
                advanced.durationTransition = generateDurationTransition(with: advanced.duration)
            }
            // 保存到 UserDefaults
            saveOptions()
        }
    }
    var exception = DEFAULT_OPTIONS.exception {
        didSet {
            // 更新 applicationsDict
            exception.applicationsDict = generateApplicationsDict(with: exception.applications)
            // 保存到 UserDefaults
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
        // 锁定
        readingOptionsLock = true
        // 配置项如果不存在则尝试用当前设置(默认设置)保存一次
        if UserDefaults.standard.object(forKey: "optionsExist") == nil { saveOptions() }
        // 基础
        basic.smooth = UserDefaults.standard.bool(forKey: "smooth")
        basic.reverse = UserDefaults.standard.bool(forKey: "reverse")
        basic.autoLaunch = UserDefaults.standard.bool(forKey: "autoLaunch")
        // 高级
        advanced.step = UserDefaults.standard.double(forKey: "step")
        advanced.speed = UserDefaults.standard.double(forKey: "speed")
        advanced.duration = UserDefaults.standard.double(forKey: "duration")
        advanced.durationTransition = generateDurationTransition(with: advanced.duration)
        advanced.precision = UserDefaults.standard.double(forKey: "precision")
        // 例外
        exception.whitelist = UserDefaults.standard.bool(forKey: "whitelist")
        exception.applications = try! decoder.decode(Array.self, from: UserDefaults.standard.value(forKey: "applications") as! Data) as [ExceptionalApplication]
        exception.applicationsDict = generateApplicationsDict(with: exception.applications)
        // 解锁
        readingOptionsLock = false
    }
    
    // 写入到 UserDefaults
    func saveOptions() {
        if !readingOptionsLock {
            // 标识配置项存在
            UserDefaults.standard.set("optionsExist", forKey:"optionsExist")
            // 基础
            UserDefaults.standard.set(basic.smooth, forKey:"smooth")
            UserDefaults.standard.set(basic.reverse, forKey:"reverse")
            UserDefaults.standard.set(basic.autoLaunch, forKey:"autoLaunch")
            // 高级
            UserDefaults.standard.set(advanced.step, forKey:"step")
            UserDefaults.standard.set(advanced.speed, forKey:"speed")
            UserDefaults.standard.set(advanced.duration, forKey:"duration")
            UserDefaults.standard.set(advanced.precision, forKey:"precision")
            // 例外
            UserDefaults.standard.set(exception.whitelist, forKey:"whitelist")
            UserDefaults.standard.set(try! encoder.encode(exception.applications), forKey: "applications")
        }
    }
    
    // 生成 applicationsDict 对象, 用于快速查找
    private func generateApplicationsDict(with applications: [ExceptionalApplication]) -> [String: ExceptionalApplication] {
        var applicationsDict = [String: ExceptionalApplication]()
        applications.forEach { (application) in
            applicationsDict[application.bundleId] = application
        }
        return applicationsDict
    }
    // 计算插值用的 durationTransition, 用于 lerp 函数直接使用
    private func generateDurationTransition(with duration: Double) -> Double {
        // 上界, 此处需要与界面的 Slider 上界保持同步, 并添加 0.2 的偏移令结果不为 0
        let upperLimit = 5.0 + 0.2
        // 生成数据 (https://www.wolframalpha.com/input/?i=1+-+(sqrt+x%2F5)+%3D+y)
        return 1-(advanced.duration/upperLimit).squareRoot()
    }
    
}
