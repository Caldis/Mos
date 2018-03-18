//
//  Utils.swift
//  Mos
//  实用方法
//  Created by Caldis on 2017/3/24.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

// 实用方法
class Utils {
    
    // 禁止重复运行
    class func preventMultiRunning() {
        // 获取自己的 BundleId
        let mainBundleID = Bundle.main.bundleIdentifier!
        // 如果检测到在运行, 则自杀
        if NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).count > 1 {
            NSApp.terminate(nil)
        }
    }
    
    // 从 StoryBroad 获取一个特定 Controller 的实例
    private static var storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
    class func instantiateControllerFromStoryboard<Controller>(withIdentifier identifier: String) -> Controller {
        let id = NSStoryboard.SceneIdentifier(rawValue: identifier)
        guard let viewController = storyboard.instantiateController(withIdentifier: id) as? Controller else {
            fatalError("Can't find Controller: \(id)")
        }
        return viewController
    }
    
}
