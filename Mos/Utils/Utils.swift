//
//  Utils.swift
//  Mos
//  实用方法
//  Created by Caldis on 2017/3/24.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa
import LoginServiceKit

// 实用方法
public class Utils {
    
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
    
    // 菜单
    class func attachImage(to menuItem:NSMenuItem, withImage image: NSImage) {
        menuItem.image = image
        menuItem.image?.size = NSSize(width: 13, height: 13)
    }
    @discardableResult class func addMenuItem(to menuControl:NSMenu, title: String, icon: NSImage, action: Selector?, target: AnyObject? = nil, represent: Any? = nil) -> NSMenuItem {
        let menuItem = menuControl.addItem(withTitle: title, action: action, keyEquivalent: "")
        menuItem.target = target ?? menuControl
        menuItem.representedObject = represent
        attachImage(to: menuItem, withImage: icon)
        return menuItem
    }
    @discardableResult class func addMenuItemWithSeparator(to menuControl:NSMenu, title: String, icon: NSImage, action: Selector?, target: Any? = nil, represent: Any? = nil) -> NSMenuItem {
        menuControl.addItem(NSMenuItem.separator())
        return addMenuItem(to: menuControl, title: title, icon: icon, action: action)
    }
    
    // 动画
    // 需要设置 allowsImplicitAnimation = true 才能让 contentSize 有动画, https://stackoverflow.com/a/46946957/6727040
    class func groupAnimatorContainer(_ group: (NSAnimationContext?)->Void, completionHandler: @escaping ()->Void = {()}) {
        if #available(OSX 10.12, *) {
            NSAnimationContext.runAnimationGroup({ (context) -> Void in
                context.duration = ANIMATION.duration
                context.allowsImplicitAnimation = true
                group(context)
            }, completionHandler: completionHandler)
        } else {
            group(nil)
            completionHandler()
        }
    }
    class func groupAnimatorContainer(_ group: (NSAnimationContext?)->Void, headHandler: @escaping ()->Void = {()}, completionHandler: @escaping ()->Void = {()}) {
        headHandler()
        groupAnimatorContainer(group, completionHandler: completionHandler)
    }
    // https://nyrra33.com/2017/12/21/rotating-a-view-is-not-easy/
    class func groupAnimatorRotate(with view: NSView, angle: CGFloat) {
        if let layer = view.layer, let animatorLayer = view.animator().layer {
            // 设定中心点
            layer.position = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // 用 CATransform3DMakeRotation 才能保证按中心旋转
            animatorLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }
    }
    
    // 禁止重复运行
    // killExist = true 则杀掉已有进程, 否则自杀
    class func preventMultiRunning(killExist kill: Bool = false) {
        // 自己的 BundleId
        let mainBundleID = Bundle.main.bundleIdentifier!
        // 如果检测到在运行
        if NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID).count > 1 {
            if kill {
                let runningInst = NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID)[0]
                runningInst.terminate()
                NSLog("Terminate: Other instance", runningInst.processIdentifier)
            } else {
                NSApp.terminate(nil)
                NSLog("Terminate: Suicide")
            }
        }
    }
    
    // 从 StoryBroad 获取一个特定 Controller 的实例
    private static let storyboard = NSStoryboard(name: "Main", bundle: nil)
    class func instantiateControllerFromStoryboard<Controller>(withIdentifier identifier: String) -> Controller {
        let id = identifier
        guard let controller = storyboard.instantiateController(withIdentifier: id) as? Controller else {
            fatalError("Can't find Controller: \(id)")
        }
        return controller
    }
    
    // 辅助功能权限相关
    // 来源: http://see.sl088.com/wiki/Mac%E5%BC%80%E5%8F%91_%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90
    // 查询是否有辅助功能权限
    class func isHadAccessibilityPermissions() -> Bool{
        return AXIsProcessTrusted()
    }
    // 申请辅助功能权限
    class func requireAccessibilityPermissions() {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let privOptions = [trusted: true] as CFDictionary
        AXIsProcessTrustedWithOptions(privOptions)
    }
    
    // Dock 图标控制
    static var isDockIconVisible = false
    class func showDockIcon() {
        if !Utils.isDockIconVisible {
            NSApp.setActivationPolicy(NSApplication.ActivationPolicy.regular)
            isDockIconVisible = true
        }
    }
    class func hideDockIcon() {
        if WindowManager.shared.refs.count == 1 {
            NSApp.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
            isDockIconVisible = false
        }
    }
    class func toggleDockIcon() {
        if isDockIconVisible {
            hideDockIcon()
        } else {
            showDockIcon()
        }
    }
    
    // 匹配字符
    class func extractRegexMatches(target: String = "", pattern: String) -> String {
        do {
            let pattern = #"\/?.*\.app"#
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: target.count)
            let result = regex.firstMatch(in: target, options: [], range: range)
            if let validResult = result {
                return NSString(string: target).substring(with: validResult.range) as String
            } else {
                return target
            }
        } catch {
            return target
        }
    }
    // 移除字符
    class func removingRegexMatches(target: String = "", pattern: String, replaceWith: String = "") -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: target.count)
            return regex.stringByReplacingMatches(in: target, options: [], range: range, withTemplate: replaceWith)
        } catch {
            return target
        }
    }
    
    // 检测按键
    class func isKey(_ event: CGEvent, _ keyCodes: [CGKeyCode]) -> Bool {
        return keyCodes.contains(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
    }
    class func isMaskRetain(_ event: CGEvent, _ mask: CGEventFlags) -> Bool {
        return event.flags.rawValue & mask.rawValue != 0
    }
    class func isMaskRelease(_ event: CGEvent, _ mask: CGEventFlags) -> Bool {
        return event.flags.rawValue & mask.rawValue == 0
    }
    class func isKeyDown(_ event: CGEvent, _ set: ( codes: [CGKeyCode], mask: CGEventFlags )) -> Bool {
        return isKey(event, set.codes) && isMaskRetain(event, set.mask)
    }
    class func isKeyUp(_ event: CGEvent, _ set: ( codes: [CGKeyCode], mask: CGEventFlags )) -> Bool {
        return isKey(event, set.codes) && isMaskRelease(event, set.mask)
    }
    
    // 从路径获取应用图标
    class func getApplicationIcon(fromPath path: String?) -> NSImage {
        guard let validPath = path else {
            return NSWorkspace.shared.icon(forFile: "")
        }
        // 尝试完整路径对应的 Bundle 获取
        if let validBundle = Bundle.init(url: URL.init(fileURLWithPath: validPath)) {
            return NSWorkspace.shared.icon(forFile: validBundle.bundlePath)
        }
        // 尝试从子路径对应的 Bundle 获取
        let subPath = extractRegexMatches(target: validPath, pattern: #"\/?.*\.app"#)
        if let validBundle = Bundle.init(url: URL.init(fileURLWithPath: subPath)) {
            return NSWorkspace.shared.icon(forFile: validBundle.bundlePath)
        }
        // 从 Path 关联的 Bundle 获取
        return NSWorkspace.shared.icon(forFile: validPath)
    }
    // 从路径获取应用名称
    class func getApplicationName(fromPath path: String?) -> String {
        guard let validPath = path else {
            return "Invalid Name"
        }
        // 尝试完整路径对应的 Bundle 获取
        if let validBundle = Bundle.init(url: URL.init(fileURLWithPath: validPath)) {
            return (
                validBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                validBundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                parseName(fromPath: validPath)
            )
        }
        // 尝试从子路径对应的 Bundle 获取
        let subPath = extractRegexMatches(target: validPath, pattern: #"\/?.*\.app"#)
        if let validBundle = Bundle.init(url: URL.init(fileURLWithPath: subPath)) {
            return (
                validBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                validBundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                parseName(fromPath: validPath)
            )
        }
        return parseName(fromPath: validPath)
    }
    class func parseName(fromPath path: String) -> String {
        let applicationRawName = FileManager().displayName(atPath: path).removingPercentEncoding!
        return Utils.removingRegexMatches(target: applicationRawName, pattern: ".app")
    }
    
    static var runningApplicationThreshold = 60.0
    static var runningApplicationCache = [String: NSRunningApplication]()
    static var runningApplicationDetectTime = [String: Double]()
    class func getRunningApplicationProcessIdentifier(withBundleIdentifier bundleIdentifier: String) -> NSRunningApplication? {
        let now = NSDate().timeIntervalSince1970
        if now - (runningApplicationDetectTime[bundleIdentifier] ?? 0.0) > runningApplicationThreshold {
            let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            runningApplicationCache[bundleIdentifier] = runningApplications.count > 0 ? runningApplications[0] : nil
            runningApplicationDetectTime[bundleIdentifier] = now
        }
        return runningApplicationCache[bundleIdentifier] ?? nil
    }
    
    class func debounce(delay: Int, action: @escaping (() -> Void)) -> () -> Void {
        var lastFireTime = DispatchTime.now()
        let dispatchDelay = DispatchTimeInterval.milliseconds(delay)

        return {
            lastFireTime = DispatchTime.now()
            let dispatchTime: DispatchTime = DispatchTime.now() + dispatchDelay
            DispatchQueue.main.asyncAfter(deadline: dispatchTime) {
                let when: DispatchTime = lastFireTime + dispatchDelay
                let now = DispatchTime.now()
                if now.rawValue >= when.rawValue {
                    action()
                }
            }
        }
    }
}
