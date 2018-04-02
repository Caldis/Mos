//
//  ExceptionalApplication.swift
//  Mos
//  例外的应用程序对象
//  Created by Caldis on 2018/2/20.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

struct ExceptionalApplication: Codable {
    
    // 应用信息
    var path: String        // 路径
    var title: String       // 名称
    var bundleId: String    // bundleId
    
    // 常规
    var smooth: Bool
    var reverse: Bool
    
    // 高级 ( 为 2.1 后新增属性, 需要设为 Optional 防止报错 )
    var step: Double?
    var speed: Double?
    var duration: Double?
    var durationTransition: Double?
    
    // 热键 ( 为 2.1 后新增属性, 需要设为 Optional 防止报错 )
    var shift: Int?
    var block: Int?
    
    init(path: String, title: String, bundleId: String) {
        // 应用信息
        self.path = path
        self.title = title
        self.bundleId = bundleId
        // 常规
        self.smooth = Options.DEFAULT_OPTIONS.basic.smooth
        self.reverse = Options.DEFAULT_OPTIONS.basic.reverse
        // 高级
        self.step = Options.DEFAULT_OPTIONS.advanced.step
        self.speed = Options.DEFAULT_OPTIONS.advanced.speed
        self.duration = Options.DEFAULT_OPTIONS.advanced.duration
        self.durationTransition = Options.DEFAULT_OPTIONS.advanced.durationTransition
        // 热键
        self.shift = Options.DEFAULT_OPTIONS.advanced.shift
        self.block = Options.DEFAULT_OPTIONS.advanced.block
    }
    
}
