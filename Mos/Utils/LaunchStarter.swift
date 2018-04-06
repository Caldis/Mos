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
        let appPath = Bundle.main.bundlePath
        if on {
            LoginServiceKit.addLoginItems(at: appPath)
        } else {
            LoginServiceKit.removeLoginItems(at: appPath)
        }
    }
    
}
