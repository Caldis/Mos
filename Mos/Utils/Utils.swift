//
//  Utils.swift
//  Mos
//  实用方法
//  Created by Caldis on 2017/3/24.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

// 实用方法
public class Utils {
    
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
            } else {
                NSApp.terminate(nil)
            }
        }
    }
    
    // 提示状态栏图标已隐藏
    class func notificateUserStatusBarIconIsHidden() {
        // 如果状态栏图标隐藏
        if Options.shared.global.hideStatusItem {
            // 定义通知
            let notification = NSUserNotification()
            notification.title = "Mos"
            notification.subtitle = i18n.mosIsRunningInThebackground
            notification.informativeText = i18n.mosStatusBarIconIsHidden
            notification.otherButtonTitle = i18n.gotIt
            notification.actionButtonTitle = i18n.showIt
            // 发送通知
            NSUserNotificationCenter.default.deliver(notification)
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
    
    // 移除字符
    class func removingRegexMatches(target: String, pattern: String, replaceWith: String = "") -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options.caseInsensitive)
            let range = NSMakeRange(0, target.count)
            return regex.stringByReplacingMatches(in: target, options: [], range: range, withTemplate: replaceWith)
        } catch {
            return target
        }
    }
    
    // 获取应用名称
    class func getApplicationName(from path: URL) -> String {
        let applicationRawName = FileManager().displayName(atPath: String(describing: path)).removingPercentEncoding!
        return Utils.removingRegexMatches(target: applicationRawName, pattern: ".app|.APP")
    }
    
    // 检测按键
    class func isControlDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return flags.rawValue & CGEventFlags.maskControl.rawValue != 0 && (keyCode == MODIFIER_KEY.controlLeft || keyCode == MODIFIER_KEY.controlRight)
    }
    class func isControlUp(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return flags.rawValue & CGEventFlags.maskControl.rawValue == 0 && (keyCode == MODIFIER_KEY.controlLeft || keyCode == MODIFIER_KEY.controlRight)
    }
    class func isOptionDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return flags.rawValue & CGEventFlags.maskAlternate.rawValue != 0 && (keyCode == MODIFIER_KEY.optionLeft || keyCode == MODIFIER_KEY.optionRight)
    }
    class func isOptionUp(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return flags.rawValue & CGEventFlags.maskAlternate.rawValue == 0 && (keyCode == MODIFIER_KEY.optionLeft || keyCode == MODIFIER_KEY.optionRight)
    }
    class func isCommandDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return flags.rawValue & CGEventFlags.maskCommand.rawValue != 0 && (keyCode == MODIFIER_KEY.commandLeft || keyCode == MODIFIER_KEY.commandRight)
    }
    class func isCommandUp(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return flags.rawValue & CGEventFlags.maskCommand.rawValue == 0 && (keyCode == MODIFIER_KEY.commandLeft || keyCode == MODIFIER_KEY.commandRight)
    }
    class func isShiftDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return flags.rawValue & CGEventFlags.maskShift.rawValue != 0 && (keyCode == MODIFIER_KEY.shiftLeft || keyCode == MODIFIER_KEY.shiftRight)
    }
    class func isShiftUp(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return flags.rawValue & CGEventFlags.maskShift.rawValue != 0 && (keyCode == MODIFIER_KEY.shiftLeft || keyCode == MODIFIER_KEY.shiftRight)
    }
    
    // 从 PID 获取进程名称
    class func getApplicationBundleIdFrom(pid: pid_t) -> String? {
        if let runningApps = NSRunningApplication.init(processIdentifier: pid) {
            return runningApps.bundleIdentifier
        } else {
            return nil
        }
    }
    class func oldGetApplicationBundleIdFrom(pid: pid_t) -> String? {
        // 更新列表
        let runningApps = NSWorkspace.shared.runningApplications
        if let matchApp = runningApps.filter({$0.processIdentifier == pid}).first {
            // 如果找到 bundleId 则返回, 不然则判定为子进程, 通过查找其父进程Id, 递归查找其父进程的bundleId
            if let bundleId = matchApp.bundleIdentifier {
                return bundleId as String?
            } else {
                let ppid = ProcessUtils.getParentPid(from: matchApp.processIdentifier)
                return ppid==1 ? nil : getApplicationBundleIdFrom(pid: ppid)
            }
        } else {
            return nil
        }
    }
}
