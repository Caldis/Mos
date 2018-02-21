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
    static func preventMultiRunning() {
        // 获取自己的 BundleId
        let mainBundleID = Bundle.main.bundleIdentifier!
        // 如果检测到在运行, 则自杀
        if NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).count > 1 {
            NSApp.terminate(nil)
        }
    }
    
}

// 管理开机启动项
// 来源: https://gist.github.com/plapier/f8e1dde1b1624dfbb3e4
@available(*, deprecated, message:"LSSharedFileList will deprecated in feature.")
class LaunchStarter {
    
    static func applicationIsInStartUpItems() -> Bool {
        return (LaunchStarter.itemReferencesInLoginItems().existingReference != nil)
    }
    
    static func itemReferencesInLoginItems() -> (existingReference: LSSharedFileListItem?, lastReference: LSSharedFileListItem?) {
        let appURL = NSURL.fileURL(withPath: Bundle.main.bundlePath)
        if let loginItemsRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue() as LSSharedFileList? {
            let loginItems = LSSharedFileListCopySnapshot(loginItemsRef, nil).takeRetainedValue() as NSArray
            let lastItemRef = loginItems.lastObject as! LSSharedFileListItem
            
            for loginItem in loginItems.enumerated() {
                let currentItemRef: LSSharedFileListItem = loginItem.element as! LSSharedFileListItem
                if let itemURL = LSSharedFileListItemCopyResolvedURL(currentItemRef, 0, nil) {
                    if (itemURL.takeRetainedValue() as NSURL).isEqual(appURL) {
                        return (currentItemRef, lastItemRef)
                    }
                }
            }
            return (nil, lastItemRef)
        }
        
        return (nil, nil)
    }
    
    // 切换是否开机加入LoginItems
    static func toggleLaunchAtStartup() {
        let itemReferences = LaunchStarter.itemReferencesInLoginItems()
        let shouldBeToggled = (itemReferences.existingReference == nil)
        if shouldBeToggled {
            LaunchStarter.enableLaunchAtStartup()
        } else {
            LaunchStarter.disableLaunchAtStartup()
        }
    }
    
    // 加入LoginItems
    static func enableLaunchAtStartup() {
        let itemReferences = LaunchStarter.itemReferencesInLoginItems()
        if let loginItemsRef = LSSharedFileListCreate( nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue() as LSSharedFileList? {
         let appUrl = NSURL.fileURL(withPath: Bundle.main.bundlePath) as CFURL
            LSSharedFileListInsertItemURL(loginItemsRef, itemReferences.lastReference, nil, nil, appUrl, nil, nil)
        }
    }

    // 从LoginItems移除
    static func disableLaunchAtStartup() {
        let itemReferences = LaunchStarter.itemReferencesInLoginItems()
        if let loginItemsRef = LSSharedFileListCreate( nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue() as LSSharedFileList? {
            if let itemRef = itemReferences.existingReference {
                LSSharedFileListItemRemove(loginItemsRef,itemRef);
            }
        }
    }
    
}
