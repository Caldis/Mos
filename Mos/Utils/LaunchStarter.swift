//
//  LaunchStarter.swift
//  Mos
//  管理开机启动项
//  Created by Caldis on 2018/2/24.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa
import LoginServiceKit

class LaunchStarter {
    
    // 切换自启
    class func launchAtStartup(on: Bool) {
        let bundlePath = Bundle.main.bundlePath
        if on {
            if !LoginServiceKit.isExistLoginItems(at: bundlePath) {
                LoginServiceKit.addLoginItems(at: bundlePath)
            }
        } else {
            LoginServiceKit.removeLoginItems(at: bundlePath)
        }
    }
}
