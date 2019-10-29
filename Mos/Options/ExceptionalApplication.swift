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
    var name: String?
    var path: String?
    var bundleId: String
    // 开关 (smooth 及 reverse 不走这个)
    var followGlobal = false
    // 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT()
    
    init(path: String, bundleId: String) {
        // 基础
        self.path = path
        self.bundleId = bundleId
    }
    init(name: String, bundleId: String) {
        // 基础
        self.name = name
        self.bundleId = bundleId
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 基础
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? nil
        self.path = try container.decodeIfPresent(String.self, forKey: .path) ?? nil
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId) ?? ""
        // 开关
        self.followGlobal = try container.decodeIfPresent(Bool.self, forKey: .followGlobal) ?? false
        // 滚动
        self.scroll = try container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.self, forKey: .scroll) ?? OPTIONS_SCROLL_DEFAULT()
    }
    
    static func == (lhs: ExceptionalApplication, rhs: ExceptionalApplication) -> Bool {
        return lhs.bundleId == rhs.bundleId
    }
}
