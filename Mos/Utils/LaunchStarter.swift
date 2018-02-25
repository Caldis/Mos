//
//  LaunchStarter.swift
//  Mos
//  管理开机启动项
//  Created by Caldis on 2018/2/24.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

// 管理开机启动项
// 来源: https://gist.github.com/plapier/f8e1dde1b1624dfbb3e4
@available(*, deprecated, message:"LSSharedFileList will deprecated in feature.")
class LaunchStarter {
    
    // 检测是否在开机启动项中
    private class func applicationIsInStartUpItems() -> Bool {
        return (itemReferencesInLoginItems().existingReference != nil)
    }
    private class func itemReferencesInLoginItems() -> (existingReference: LSSharedFileListItem?, lastReference: LSSharedFileListItem?) {
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
    
    // 切换自启
    class func toggleLaunchAtStartup() {
        let itemReferences = itemReferencesInLoginItems()
        let shouldBeToggled = (itemReferences.existingReference == nil)
        if shouldBeToggled {
            LaunchStarter.enableLaunchAtStartup()
        } else {
            LaunchStarter.disableLaunchAtStartup()
        }
    }
    
    // 启用自启 (加入 LoginItems)
    class func enableLaunchAtStartup() {
        let itemReferences = itemReferencesInLoginItems()
        if let loginItemsRef = LSSharedFileListCreate( nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue() as LSSharedFileList? {
            let appUrl = NSURL.fileURL(withPath: Bundle.main.bundlePath) as CFURL
            LSSharedFileListInsertItemURL(loginItemsRef, itemReferences.lastReference, nil, nil, appUrl, nil, nil)
        }
    }
    
    // 禁止自启 (从 LoginItems 移除)
    class func disableLaunchAtStartup() {
        let itemReferences = itemReferencesInLoginItems()
        if let loginItemsRef = LSSharedFileListCreate( nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue() as LSSharedFileList? {
            if let itemRef = itemReferences.existingReference {
                LSSharedFileListItemRemove(loginItemsRef,itemRef);
            }
        }
    }
    
}
