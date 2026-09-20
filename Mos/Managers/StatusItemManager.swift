//
//  StatusItemManager.swift
//  Mos
//  管理状态栏图标以及初始化
//  Created by Caldis on 2018/3/7.
//  Copyright © 2018年 Caldis. All rights reserved.
//
import Cocoa

class StatusItemManager: NSMenu, NSMenuDelegate {

    // 状态栏引用
    static let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let item = StatusItemManager.statusItem

    // 菜单不挂在 item.menu 上时, 由这里持有唯一的强引用 (item.button 的 target 不持有)
    private(set) static var shared: StatusItemManager?

    // 弹出菜单期间置位, 防止 performClick 递归回到按钮响应
    private var isPoppingUpMenu = false

    // 初始化
    override func awakeFromNib() {
        NSLog("Module initialized: StatusItemManager")
        StatusItemManager.shared = self
        // 设置图标/行为
        item.button?.image = #imageLiteral(resourceName: "AppStatusBarIcon")
        // 设置事件响应
        delegate = self
        item.button?.target = self
        item.button?.action = #selector(onStatusItemClick)
        _ = item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // 点击方式与图标明暗跟随配置
        Options.shared.observe([.general, .scroll]) { _ in StatusItemManager.syncWithOptions() }
        StatusItemManager.syncWithOptions()
    }

}

/**
 * 点击响应
 **/
extension StatusItemManager {
    // 图标被点击
    @objc func onStatusItemClick() {
        let event = NSApp.currentEvent
        let outcome = StatusItemSecondaryClickAction.outcome(
            isSecondaryClick: StatusItemManager.isSecondaryClick(event),
            action: Options.shared.general.statusItemSecondaryClickAction,
            isAccessibilityTrusted: AXIsProcessTrusted()
        )
        switch outcome {
        case .showMenu:
            popUpStatusItemMenu()
        case .openPreferences:
            preferencesClick()
        case .toggleScroll(let option):
            toggleScrollOption(option)
        }
    }
    // 右键, 或按住 Control 的左键 (macOS 的次要点击约定)
    class func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event = event else { return false }
        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }
    // 弹出菜单, 临时挂到 status item 上, 由系统负责定位/高亮/键盘导航
    private func popUpStatusItemMenu() {
        guard !isPoppingUpMenu else { return }
        isPoppingUpMenu = true
        item.menu = self
        item.button?.performClick(nil)
        item.menu = nil
        isPoppingUpMenu = false
    }
    // 快速开关滚动选项, 图标由 Options 订阅刷新
    private func toggleScrollOption(_ option: ScrollToggleOption) {
        let scroll = Options.shared.scroll
        option.setEnabled(!option.isEnabled(in: scroll), in: scroll)
    }
}

/**
 * 菜单响应
 **/
extension StatusItemManager {
    // 打开菜单
    func menuWillOpen(_ menu: NSMenu) {
        onMenuClick()
    }
    @objc func onMenuClick()  {
        // 无辅助功能选项显示要求权限菜单
        guard AXIsProcessTrusted() else {
            buildRequireAccessibilityMenu()
            return
        }
        // DEBUG: 直接弹出设置窗口
        #if DEBUG
        buildOptionMenu()
        #else
        // 当按下 option 键显示特殊菜单
        guard NSApp.currentEvent?.modifierFlags.contains(.option) != true else {
            buildOptionMenu()
            return
        }
        // 弹出菜单
        buildNormalMenu()
        #endif
    }
}

/**
 * 菜单构建
 **/
extension StatusItemManager {
    // 无辅助功能访问权限菜单
    @objc func buildRequireAccessibilityMenu() {
        let menu: NSMenu = self
        menu.removeAllItems()
        menu.addItem(withTitle: NSLocalizedString("Needs access to Accessibility controls", comment: ""), action: #selector(accessibilityRequire), keyEquivalent: "").target = self
        // Quit
        Utils.addMenuItemWithSeparator(to: menu, title: NSLocalizedString("Quit", comment: ""), icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
    }
    @objc func accessibilityRequire() {
        Utils.requireAccessibilityPermissions()
    }
    // 按下 Option 按钮的菜单
    @objc func buildOptionMenu() {
        let menu: NSMenu = self
        // Reset
        menu.removeAllItems()
        // Monitor
        Utils.addMenuItem(to: menu, title: "Debug: Event Monitor", action: #selector(monitorClick))
        // HID++ Debug
        Utils.addMenuItem(to: menu, title: "Debug: HID++", action: #selector(hidDebugClick))
        // Toast Debug
        Utils.addMenuItem(to: menu, title: "Debug: Toast", action: #selector(toastDebugClick))
        // Preferences
        Utils.addMenuItem(to: menu, title: NSLocalizedString("Preferences", comment: ""), icon: #imageLiteral(resourceName: "SF.gauge"), action: #selector(preferencesClick))
        // Quit
        Utils.addMenuItemWithSeparator(to: menu, title: NSLocalizedString("Quit", comment: ""), icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
    }
    // 常规菜单
    @objc func buildNormalMenu() {
        let menu: NSMenu = self
        // Reset
        menu.removeAllItems()
        // Preferences
        Utils.addMenuItem(to: menu, title: NSLocalizedString("Preferences", comment: ""), icon: #imageLiteral(resourceName: "SF.gauge"), action: #selector(preferencesClick))
        // Quit
        Utils.addMenuItemWithSeparator(to: menu, title: NSLocalizedString("Quit", comment: ""), icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
    }
    @objc func monitorClick() {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController)
    }
    @objc func hidDebugClick() {
        LogiCenter.shared.showDebugPanel()
    }
    @objc func toastDebugClick() {
        Toast.showTestPanel()
    }
    @objc func preferencesClick() {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
    }
    @objc func quitClick() {
        NSApplication.shared.terminate(self)
    }
}

/**
 * 图标显示
 **/
extension StatusItemManager {
    // 显示状态栏图标
    class func showStatusItem() {
        if #available(OSX 10.12, *) {
            self.statusItem.isVisible = true
        } else {
            self.statusItem.length = NSStatusItem.variableLength
        }
    }
    // 隐藏状态栏图标
    class func hideStatusItem() {
        if #available(OSX 10.12, *) {
            self.statusItem.isVisible = false
        } else {
            self.statusItem.length = 0.0
        }
    }
    // 同步点击方式与图标明暗
    //
    // 右键保持默认行为时菜单常驻 item.menu, 点击响应与旧版本完全一致;
    // 只有用户给右键指定了其它行为, 才把菜单摘下来改由按钮事件接管, 以区分左右键
    class func syncWithOptions() {
        let action = Options.shared.general.statusItemSecondaryClickAction
        self.statusItem.menu = action == .menu ? self.shared : nil
        self.statusItem.button?.appearsDisabled = StatusItemSecondaryClickAction.iconAppearsDisabled(
            action: action,
            isSmoothEnabled: Options.shared.scroll.smooth,
            isReverseEnabled: Options.shared.scroll.reverse
        )
    }
}
