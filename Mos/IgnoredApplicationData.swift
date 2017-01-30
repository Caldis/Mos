//
//  IgnoreApplicationData.swift
//  Mos
//  忽略的应用程序对象
//  Created by Cb on 2017/1/29.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class IgnoredApplication: NSObject, NSCoding {
    
    var notSmooth: Bool
    var notReverse: Bool
    var icon: NSImage?
    var title: String
    var bundleId: String
    
    override init() {
        self.notSmooth = true
        self.notReverse = true
        self.icon = nil
        self.title = String()
        self.bundleId = String()
    }
    
    init(notSmooth: Bool, notReverse: Bool, icon: NSImage?, title: String, bundleId: String) {
        self.notSmooth = notSmooth
        self.notReverse = notReverse
        self.icon = icon
        self.title = title
        self.bundleId = bundleId
    }
    
    //从object解析回来
    required init(coder decoder: NSCoder) {
        self.notSmooth = decoder.decodeBool(forKey: "notSmooth")
        self.notReverse = decoder.decodeBool(forKey: "notReverse")
        self.icon = decoder.decodeObject(forKey: "icon") as? NSImage ?? nil
        self.title = decoder.decodeObject(forKey: "title") as? String ?? ""
        self.bundleId = decoder.decodeObject(forKey: "bundleId") as? String ?? ""
    }
    
    //编码成object
    func encode(with coder: NSCoder) {
        coder.encode(self.notSmooth, forKey:"notSmooth")
        coder.encode(self.notReverse, forKey:"notReverse")
        coder.encode(self.icon, forKey:"icon")
        coder.encode(self.title, forKey:"title")
        coder.encode(self.bundleId, forKey:"bundleId")
    }
}
