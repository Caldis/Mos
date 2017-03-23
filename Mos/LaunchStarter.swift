//
//  LaunchStarter.swift
//  Mos
//  用于管理开机启动项
//  Created by Cb on 2017/3/23.
//  Copyright © 2017年 Cb. All rights reserved.
//
//  With help from: https://gist.github.com/plapier/f8e1dde1b1624dfbb3e4

import Foundation

@available(*, deprecated, message:"LSSharedFileList will deprecated in feature.")
class LaunchStarter {
    
    static func applicationIsInStartUpItems() -> Bool {
        return (LaunchStarter.itemReferencesInLoginItems().existingReference != nil)
    }

    static func itemReferencesInLoginItems() -> (existingReference: LSSharedFileListItem?, lastReference: LSSharedFileListItem?) {
        if let appURL : NSURL = NSURL.fileURL(withPath: Bundle.main.bundlePath) as NSURL? {
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
            if let appUrl = NSURL.fileURL(withPath: Bundle.main.bundlePath) as CFURL? {
                LSSharedFileListInsertItemURL(loginItemsRef, itemReferences.lastReference, nil, nil, appUrl, nil, nil)
            }
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
