//
//  StatusItemPopoverController.swift
//  Mos
//  状态栏弹出
//  Created by Caldis on 2018/12/29.
//  Copyright © 2018 Caldis. All rights reserved.
//

import Cocoa

class StatusItemPopoverViewController: NSViewController {
    
    // 点击监听
    var clickEventMonitor: EventMonitor?
    // 引用
    var currentPopover: NSPopover!
    var currentViewController: NSViewController!
    var currentViewControllers = [NSViewController]()
    // 控件
    @IBOutlet var menuControl: NSMenu!
    @IBOutlet var preferencesContainerView: NSView!
    
    // 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        // 获取 Popover
        currentPopover = PopoverManager.shared.refs[POPOVER_IDENTIFIER.preferencesPopoverController]!
        // 初始化分页
        currentViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.exception) as NSViewController
        preferencesContainerView!.addSubview(currentViewController.view)
        currentPopover.contentSize = NSSize.init(
            width: currentPopover.contentViewController!.view.frame.width,
            height: currentViewController.view.frame.height + PANEL_PADDING
        )
    }
    override func viewWillAppear() {
         clickEventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: hidePopover)
    }
    
    // 按钮点击
    @IBAction func monitorButtonClick(_ sender: NSButton) {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController, withTitle: "")
    }
    @IBAction func settingButtonClick(_ sender: NSButton) {
        let buttonPosition = NSPoint(x: sender.frame.origin.x, y: sender.frame.origin.y - (sender.frame.height / 2))
        menuControl.popUp(positioning: nil, at: buttonPosition, in: sender.superview)
    }
    @IBAction func menuControlPreferencesButtonClick(_ sender: NSMenuItem) {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController, withTitle: i18n.preferences)
    }
    @IBAction func menuControlQuitButtonClick(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}

/**
 * 面板控制
 **/
extension StatusItemPopoverViewController {
    
    // 隐藏
    func hidePopover(_:NSEvent?) {
        PopoverManager.shared.hidePopover(withIdentifier: POPOVER_IDENTIFIER.preferencesPopoverController)
        clickEventMonitor?.stop()
    }
    
    // 切换到特定分页
    func showTargetPanel(with targetIndex: Int) {
        // 删除并替换
        for subView in preferencesContainerView.subviews { subView.removeFromSuperview() }
        preferencesContainerView.addSubview(currentViewControllers[targetIndex].view)
        // 调整大小
        currentPopover.contentSize = NSSize.init(
            width: currentPopover.contentViewController!.view.frame.width,
            height: currentViewControllers[targetIndex].view.frame.height + PANEL_PADDING
        )
    }
}
