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
    // 常规
    var smooth: Bool
    var reverse: Bool
    // 高级
    var followGlobal: Bool
    var toggle: Int
    var block: Int
    var step: Double
    var speed: Double
    var duration: Double
    var durationTransition: Double
    
    init(path: String, bundleId: String) {
        // 基础
        self.path = path
        self.bundleId = bundleId
        // 常规
        self.smooth = Options.DEFAULT_OPTIONS.basic.smooth
        self.reverse = Options.DEFAULT_OPTIONS.basic.reverse
        // 高级
        self.followGlobal = true
        self.toggle = Options.DEFAULT_OPTIONS.advanced.toggle
        self.block = Options.DEFAULT_OPTIONS.advanced.block
        self.step = Options.DEFAULT_OPTIONS.advanced.step
        self.speed = Options.DEFAULT_OPTIONS.advanced.speed
        self.duration = Options.DEFAULT_OPTIONS.advanced.duration
        self.durationTransition = Options.DEFAULT_OPTIONS.advanced.durationTransition
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 基础
        self.path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId) ?? ""
        // 常规
        self.smooth = try container.decodeIfPresent(Bool.self, forKey: .smooth) ?? true
        self.reverse = try container.decodeIfPresent(Bool.self, forKey: .reverse) ?? true
        // 高级
        self.followGlobal = try container.decodeIfPresent(Bool.self, forKey: .followGlobal) ?? true
        self.toggle = try container.decodeIfPresent(Int.self, forKey: .toggle) ?? 0
        self.block = try container.decodeIfPresent(Int.self, forKey: .block) ?? 0
        self.step = try container.decodeIfPresent(Double.self, forKey: .step) ?? Options.DEFAULT_OPTIONS.advanced.step
        self.speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? Options.DEFAULT_OPTIONS.advanced.speed
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? Options.DEFAULT_OPTIONS.advanced.duration
        self.durationTransition = try container.decodeIfPresent(Double.self, forKey: .durationTransition) ?? Options.DEFAULT_OPTIONS.advanced.durationTransition
    }
    
    static func == (lhs: ExceptionalApplication, rhs: ExceptionalApplication) -> Bool {
        return lhs.bundleId == rhs.bundleId
    }
}
