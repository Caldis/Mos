//
//  Application.swift
//  Mos
//  应用程序对象
//  Created by Caldis on 2018/2/20.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Application: Codable, Equatable {
    
    // 基础
    var path: String // executablePath or bundlePath
    // 配置: 名称
    var displayName: String? = "" {
        didSet { Options.shared.saveOptions() }
    }
    // 配置: 继承
    var inherit = true {
        didSet { Options.shared.saveOptions() }
    }
    // 配置: 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT() {
        didSet { Options.shared.saveOptions() }
    }
    // 配置: 按钮绑定 (可选表示继承全局配置)
    var buttons: OPTIONS_BUTTONS_DEFAULT? {
        didSet { Options.shared.saveOptions() }
    }
    // 初始化
    init(path: String) {
        self.path = path
    }
    
    // Codable
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 基础
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        // 名称
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        // 继承
        inherit = try container.decodeIfPresent(Bool.self, forKey: .inherit) ?? true
        // 滚动
        scroll = try container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.self, forKey: .scroll) ?? OPTIONS_SCROLL_DEFAULT()
        // 按钮绑定
        buttons = try container.decodeIfPresent(OPTIONS_BUTTONS_DEFAULT.self, forKey: .buttons)
    }
    
    // Equatable
    static func == (a: Application, b: Application) -> Bool {
        return a.path == b.path
    }
}

/**
 * 工具函数
 */
extension Application {
    // 基本信息
    func getIcon() -> NSImage {
        return Utils.getApplicationIcon(fromPath: path)
    }
    func getName() -> String {
        if let name = displayName, name.count > 0 {
            return name
        }
        return Utils.getApplicationName(fromPath: path)
    }
    // 配置
    func getStep() -> Double {
        return inherit ? Options.shared.scroll.step : scroll.step
    }
    func getSpeed() -> Double {
        return inherit ? Options.shared.scroll.speed : scroll.speed
    }
    func getDuration() -> Double {
        return inherit ? Options.shared.scroll.durationTransition : scroll.durationTransition
    }
    // 功能
    func isSmooth(_ block: Bool) -> Bool {
        if block { return false }
        if !Options.shared.scroll.smooth { return false }
        return scroll.smooth
    }
    func isReverse() -> Bool {
        if !Options.shared.scroll.reverse { return false }
        return scroll.reverse
    }
    // 按钮绑定
    func getButtonBindings() -> [ButtonBinding] {
        return buttons?.binding ?? Options.shared.buttons.binding
    }
}
