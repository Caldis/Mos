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

    struct Update {
        static let CheckOnAppStart = "updateCheckOnAppStart"
        static let IncludingBetaVersion = "updateIncludingBetaVersion"
    }

    struct Scroll {
        static let Smooth = "smooth"
        static let Reverse = "reverse"
        static let ReverseVertical = "reverseVertical"
        static let ReverseHorizontal = "reverseHorizontal"
        static let Dash = "dash"
        static let Toggle = "toggle"
        static let Block = "block"
        static let Step = "step"
        static let Speed = "speed"
        static let Duration = "duration"
        static let DeadZone = "deadZone"
        static let SmoothSimTrackpad = "smoothSimTrackpad"
        static let SmoothVertical = "smoothVertical"
        static let SmoothHorizontal = "smoothHorizontal"
    }

    struct Button {
        static let Bindings = "buttonBindings"
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
    // 更新
    var update = OPTIONS_UPDATE_DEFAULT()
    // 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT() {
        didSet { Options.shared.saveOptions() }
    }
    // 按钮绑定
    var buttons = OPTIONS_BUTTONS_DEFAULT() {
        didSet { Options.shared.saveOptions() }
    }
    // 应用
    var application = OPTIONS_APPLICATION_DEFAULT() {
        didSet { Options.shared.saveOptions() }
    }

    /// 保留无法 decode 的 binding 原始 JSON 元素 (来自未来 Mos 版本).
    /// 在 save 时再合回去, 防止用户升级后再降级时丢失新版数据.
    fileprivate var preservedUnknownBindings: [Any] = []
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
        // 更新
        update.checkOnAppStart = UserDefaults.standard.bool(forKey: OptionItem.Update.CheckOnAppStart)
        update.includingBetaVersion = UserDefaults.standard.bool(forKey: OptionItem.Update.IncludingBetaVersion)
        // 滚动
        scroll.smooth = UserDefaults.standard.bool(forKey: OptionItem.Scroll.Smooth)
        scroll.reverse = UserDefaults.standard.bool(forKey: OptionItem.Scroll.Reverse)
        if UserDefaults.standard.object(forKey: OptionItem.Scroll.ReverseVertical) == nil {
            scroll.reverseVertical = true
        } else {
            scroll.reverseVertical = UserDefaults.standard.bool(forKey: OptionItem.Scroll.ReverseVertical)
        }
        if UserDefaults.standard.object(forKey: OptionItem.Scroll.ReverseHorizontal) == nil {
            scroll.reverseHorizontal = true
        } else {
            scroll.reverseHorizontal = UserDefaults.standard.bool(forKey: OptionItem.Scroll.ReverseHorizontal)
        }
        scroll.dash = loadScrollHotkey(forKey: OptionItem.Scroll.Dash, default: OPTIONS_SCROLL_DEFAULT().dash)
        scroll.toggle = loadScrollHotkey(forKey: OptionItem.Scroll.Toggle, default: OPTIONS_SCROLL_DEFAULT().toggle)
        scroll.block = loadScrollHotkey(forKey: OptionItem.Scroll.Block, default: OPTIONS_SCROLL_DEFAULT().block)
        scroll.step = UserDefaults.standard.double(forKey: OptionItem.Scroll.Step)
        scroll.speed = UserDefaults.standard.double(forKey: OptionItem.Scroll.Speed)
        scroll.duration = UserDefaults.standard.double(forKey: OptionItem.Scroll.Duration)
        if let storedDeadZone = UserDefaults.standard.object(forKey: OptionItem.Scroll.DeadZone) as? Double {
            scroll.deadZone = storedDeadZone
        } else {
            scroll.deadZone = OPTIONS_SCROLL_DEFAULT().deadZone
        }
        scroll.smoothSimTrackpad = UserDefaults.standard.bool(forKey: OptionItem.Scroll.SmoothSimTrackpad)
        if UserDefaults.standard.object(forKey: OptionItem.Scroll.SmoothVertical) == nil {
            scroll.smoothVertical = true
        } else {
            scroll.smoothVertical = UserDefaults.standard.bool(forKey: OptionItem.Scroll.SmoothVertical)
        }
        if UserDefaults.standard.object(forKey: OptionItem.Scroll.SmoothHorizontal) == nil {
            scroll.smoothHorizontal = true
        } else {
            scroll.smoothHorizontal = UserDefaults.standard.bool(forKey: OptionItem.Scroll.SmoothHorizontal)
        }
        // 按钮绑定
        buttons.binding = loadButtonsData()
        ButtonUtils.shared.invalidateCache()
        // 应用
        application.allowlist = UserDefaults.standard.bool(forKey: OptionItem.Application.Allowlist)
        application.applications = loadApplicationsData()
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
            // 更新
            UserDefaults.standard.set(update.checkOnAppStart, forKey: OptionItem.Update.CheckOnAppStart)
            UserDefaults.standard.set(update.includingBetaVersion, forKey: OptionItem.Update.IncludingBetaVersion)
            // 滚动
            UserDefaults.standard.set(scroll.smooth, forKey: OptionItem.Scroll.Smooth)
            UserDefaults.standard.set(scroll.reverse, forKey: OptionItem.Scroll.Reverse)
            UserDefaults.standard.set(scroll.reverseVertical, forKey: OptionItem.Scroll.ReverseVertical)
            UserDefaults.standard.set(scroll.reverseHorizontal, forKey: OptionItem.Scroll.ReverseHorizontal)
            saveScrollHotkey(scroll.dash, forKey: OptionItem.Scroll.Dash)
            saveScrollHotkey(scroll.toggle, forKey: OptionItem.Scroll.Toggle)
            saveScrollHotkey(scroll.block, forKey: OptionItem.Scroll.Block)
            UserDefaults.standard.set(scroll.step, forKey: OptionItem.Scroll.Step)
            UserDefaults.standard.set(scroll.speed, forKey: OptionItem.Scroll.Speed)
            UserDefaults.standard.set(scroll.duration, forKey: OptionItem.Scroll.Duration)
            UserDefaults.standard.set(scroll.deadZone, forKey: OptionItem.Scroll.DeadZone)
            UserDefaults.standard.set(scroll.smoothSimTrackpad, forKey: OptionItem.Scroll.SmoothSimTrackpad)
            UserDefaults.standard.set(scroll.smoothVertical, forKey: OptionItem.Scroll.SmoothVertical)
            UserDefaults.standard.set(scroll.smoothHorizontal, forKey: OptionItem.Scroll.SmoothHorizontal)
            // 应用
            UserDefaults.standard.set(application.allowlist, forKey: OptionItem.Application.Allowlist)
            if let applicationsData = application.applications.json() {
                UserDefaults.standard.set(applicationsData, forKey: OptionItem.Application.Applications)
            } else {
                NSLog("Failed to serialize applications data, skipping save")
            }
            // 按钮绑定
            saveButtonBindingsData()
        }
    }

    // 安全加载按钮绑定数据
    private func loadButtonsData() -> [ButtonBinding] {
        let rawValue = UserDefaults.standard.object(forKey: OptionItem.Button.Bindings)
        guard let data = rawValue as? Data else {
            if rawValue != nil {
                NSLog("Button bindings data has wrong type: \(type(of: rawValue)), clearing corrupted data")
                UserDefaults.standard.removeObject(forKey: OptionItem.Button.Bindings)
            }
            preservedUnknownBindings = []
            return []
        }
        let result = Self.decodeButtonBindingsWithUnknowns(from: data)
        preservedUnknownBindings = result.unknownElements
        return result.bindings
    }

    /// 容错解码 button binding 数组, 保留未识别条目原始 JSON.
    ///
    /// - 外层不是 JSON 数组 → 返回空, 视作配置丢失
    /// - 单个 binding 解析失败 → 收集到 unknownElements (raw JSON), 不丢
    ///
    /// 这种 per-binding 容错设计支持向前兼容: 未来 Mos 版本写入的未知 payload
    /// 不会导致整组绑定被擦掉, 也不会在 save 时被误删 (saveButtonBindingsData
    /// 会把 preservedUnknownBindings 重新拼回数组末尾).
    static func decodeButtonBindingsWithUnknowns(
        from data: Data
    ) -> (bindings: [ButtonBinding], unknownElements: [Any]) {
        guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            NSLog("Button bindings data is not a JSON array, returning empty")
            return (bindings: [], unknownElements: [])
        }
        let decoder = JSONDecoder()
        var bindings: [ButtonBinding] = []
        var unknown: [Any] = []
        for element in elements {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element) else {
                continue   // 完全损坏的元素 (e.g. JSON null 顶级), 真正丢掉
            }
            if let binding = try? decoder.decode(ButtonBinding.self, from: elementData) {
                bindings.append(binding)
            } else {
                unknown.append(element)
            }
        }
        if !unknown.isEmpty {
            NSLog("Preserved \(unknown.count) unparseable button binding(s) for round-trip (likely from a future Mos version)")
        }
        return (bindings: bindings, unknownElements: unknown)
    }

    /// Convenience wrapper: 只返回已识别的 bindings (供单测和不关心 unknowns 的调用方).
    static func decodeButtonBindings(from data: Data) -> [ButtonBinding] {
        return decodeButtonBindingsWithUnknowns(from: data).bindings
    }

    // 保存按钮绑定数据 (合并 preservedUnknownBindings, 不丢弃未来版本数据)
    private func saveButtonBindingsData() {
        do {
            let knownData = try encoder.encode(buttons.binding)
            guard var merged = try JSONSerialization.jsonObject(with: knownData) as? [Any] else {
                NSLog("Failed to round-trip known bindings to JSON array, skipping save")
                return
            }
            // 把保留的未知元素拼回去 (放在末尾, 不影响已知 bindings 顺序)
            merged.append(contentsOf: preservedUnknownBindings)
            let mergedData = try JSONSerialization.data(withJSONObject: merged)
            UserDefaults.standard.set(mergedData, forKey: OptionItem.Button.Bindings)
        } catch {
            NSLog("Failed to encode button bindings data: \(error), skipping save")
        }
    }

    // 加载滚动热键 (支持从旧版 Int 格式迁移)
    private func loadScrollHotkey(forKey key: String, default defaultValue: ScrollHotkey?) -> ScrollHotkey? {
        let rawValue = UserDefaults.standard.object(forKey: key)

        // 新格式: Data (JSON encoded ScrollHotkey)
        if let data = rawValue as? Data {
            do {
                return try decoder.decode(ScrollHotkey.self, from: data)
            } catch {
                NSLog("Failed to decode ScrollHotkey for \(key): \(error), using default")
                return defaultValue
            }
        }

        // 旧格式迁移: Int (keyboard keyCode only)
        if let intValue = rawValue as? Int {
            // 迁移为新格式
            let hotkey = ScrollHotkey(type: .keyboard, code: UInt16(intValue))
            saveScrollHotkey(hotkey, forKey: key)
            return hotkey
        }

        // 无值时: 检查配置是否已存在
        // 如果配置已存在但该键无值，说明用户主动删除了它，返回 nil
        // 如果配置不存在（首次启动），返回默认值
        let optionsExist = UserDefaults.standard.object(forKey: OptionItem.General.OptionsExist) != nil
        return optionsExist ? nil : defaultValue
    }

    // 保存滚动热键
    private func saveScrollHotkey(_ hotkey: ScrollHotkey?, forKey key: String) {
        guard let hotkey = hotkey else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        do {
            let data = try encoder.encode(hotkey)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            NSLog("Failed to encode ScrollHotkey for \(key): \(error), skipping save")
        }
    }

    // 安全加载应用列表数据
    private func loadApplicationsData() -> EnhanceArray<Application> {
        let defaultArray = EnhanceArray<Application>(
            matchKey: "path",
            forObserver: Options.shared.saveOptions
        )

        // 检查 UserDefaults 中的值类型
        let rawValue = UserDefaults.standard.object(forKey: OptionItem.Application.Applications)
        guard let data = rawValue as? Data else {
            if rawValue != nil {
                NSLog("Applications data has wrong type: \(type(of: rawValue)), clearing corrupted data")
                UserDefaults.standard.removeObject(forKey: OptionItem.Application.Applications)
            }
            return defaultArray
        }

        // 尝试解析
        do {
            return try EnhanceArray<Application>(
                withData: data,
                matchKey: "path",
                forObserver: Options.shared.saveOptions
            )
        } catch {
            NSLog("Failed to decode applications data: \(error), resetting to defaults")
            UserDefaults.standard.removeObject(forKey: OptionItem.Application.Applications)
            return defaultArray
        }
    }
}
