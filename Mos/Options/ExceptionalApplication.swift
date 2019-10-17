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
    var path: String
    var bundleId: String
    var followGlobal = false // 不包含 smooth 及 reverse
    // 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT()
    
    init(path: String, bundleId: String) {
        // 基础
        self.path = path
        self.bundleId = bundleId
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 基础
        self.path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId) ?? ""
        self.followGlobal = false // try container.decodeIfPresent(Bool.self, forKey: .followGlobal) ?? true
        // 滚动
        self.scroll = try container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.self, forKey: .scroll) ?? OPTIONS_SCROLL_DEFAULT()
    }
    
    static func == (lhs: ExceptionalApplication, rhs: ExceptionalApplication) -> Bool {
        return lhs.bundleId == rhs.bundleId
    }
}
