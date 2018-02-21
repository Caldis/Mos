//
//  ExceptionalApplication.swift
//  Mos
//  例外的应用程序对象
//  Created by Caldis on 2018/2/20.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

struct ExceptionalApplication:Codable {
    
    var smooth: Bool        // 平滑滚动
    var reverse: Bool       // 反向滚动
//    var icon: NSURL?        // 应用程序图标(路径)
    var title: String       // 应用程序名称
    var bundleId: String    // 应用程序 BID
    
    init(smooth: Bool, reverse: Bool, title: String, bundleId: String) {
        self.smooth = smooth
        self.reverse = reverse
//        self.icon = icon
        self.title = title
        self.bundleId = bundleId
    }
    
}
