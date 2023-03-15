//
//  ExceptionalApplication.swift
//  Mos
//  例外的应用程序对象
//  Created by Caldis on 2018/2/20.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ExceptionalApplication: Codable, Equatable {
    
    // 基础
    var path: String // executablePath or bundlePath
    // 配置: 名称
    var displayName: String? = "" {
        didSet {Options.shared.saveOptions()}
    }
    // 配置: 继承 (仅包含 Advanced 部分)
    var inherit = true {
        didSet {Options.shared.saveOptions()}
    }
    // 配置: 滚动
    var scrollBasic = OPTIONS_SCROLL_BASIC_DEFAULT()
    var scrollAdvanced = OPTIONS_SCROLL_ADVANCED_DEFAULT() {
        didSet {Options.shared.saveOptions()}
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
        scrollBasic = try container.decodeIfPresent(OPTIONS_SCROLL_BASIC_DEFAULT.self, forKey: .scrollBasic) ?? OPTIONS_SCROLL_BASIC_DEFAULT()
        scrollAdvanced = try container.decodeIfPresent(OPTIONS_SCROLL_ADVANCED_DEFAULT.self, forKey: .scrollAdvanced) ?? OPTIONS_SCROLL_ADVANCED_DEFAULT()
    }
    
    // Equatable
    static func == (a: ExceptionalApplication, b: ExceptionalApplication) -> Bool {
        return a.path == b.path
    }
}

/**
 * 工具函数
 */
extension ExceptionalApplication {
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
        return inherit ? Options.shared.scrollAdvanced.step : scrollAdvanced.step
    }
    func getSpeed() -> Double {
        return inherit ? Options.shared.scrollAdvanced.speed : scrollAdvanced.speed
    }
    func getDuration() -> Double {
        return inherit ? Options.shared.scrollAdvanced.durationTransition : scrollAdvanced.durationTransition
    }
    // 功能
    func isSmooth(_ block: Bool) -> Bool {
        if block { return false }
        if !Options.shared.scrollBasic.smooth { return false }
        return scrollBasic.smooth
    }
    func isReverse() -> Bool {
        if !Options.shared.scrollBasic.reverse { return false }
        return scrollBasic.reverse
    }
}
