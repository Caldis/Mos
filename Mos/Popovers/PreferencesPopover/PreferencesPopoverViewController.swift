//
//  PreferencesPopoverController.swift
//  Mos
//  状态栏弹出
//  Created by Caldis on 2018/12/29.
//  Copyright © 2018 Caldis. All rights reserved.
//

import Cocoa

class PreferencesPopoverViewController: NSViewController {
    
    // 点击监听
    var clickEventMonitor: EventMonitor?
    // 引用
    var currentPopover: NSPopover!
    var currentViewControllers = [NSViewController]()
    // 控件
    @IBOutlet var menuControl: NSMenu!
    @IBOutlet weak var preferencesTabSegmentControl: NSSegmentedControl!
    @IBOutlet weak var preferencesContainerView: NSView!
    
    // 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        // 获取 Popover
        currentPopover = PopoverManager.shared.refs[POPOVER_IDENTIFIER.preferencesPopoverController]!
        // 初始化分页
        for identifier in PANEL_IDENTIFIER.list {
            currentViewControllers.append(Utils.instantiateControllerFromStoryboard(withIdentifier: identifier)!)
        }
        // 显示第一个TAB分页
        showTargetPanel(with: 0)
    }
    override func viewWillAppear() {
        // 监听鼠标点击外部
        clickEventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: hidePopover)
        // 激活窗口
        NSApp.activate(ignoringOtherApps: false)
    }
    
    // 页面切换
    @IBAction func preferencesTabSegmentControlSelected(_ sender: NSSegmentedCell) {
        showTargetPanel(with: sender.selectedSegment)
    }
    
    // 按钮点击
    @IBAction func monitorButtonClick(_ sender: NSButton) {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController, withTitle: "")
    }
    @IBAction func settingButtonClick(_ sender: NSButton) {
        let buttonPosition = NSPoint(x: sender.frame.origin.x, y: sender.frame.origin.y - (sender.frame.height / 2))
        menuControl.popUp(positioning: nil, at: buttonPosition, in: sender.superview)
    }
    @IBAction func menuControlQuitButtonClick(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
    @IBAction func donateButtonClick(_ sender: NSButton) {
        
    }
    @IBAction func aboutButtonClick(_ sender: NSButton) {
        
    }
}

/**
 * 面板控制
 **/
extension PreferencesPopoverViewController {
    
    //  隐藏 Popover
    func hidePopover(_:NSEvent?) {
        PopoverManager.shared.hidePopover(withIdentifier: POPOVER_IDENTIFIER.preferencesPopoverController)
        clickEventMonitor?.stop()
    }
    
    // 切换到特定分页
    func showTargetPanel(with targetIndex: Int) {
        // 关闭动画
        // currentPopover.animates = false
        // 删除并替换
        for subView in preferencesContainerView.subviews { subView.removeFromSuperview() }
        preferencesContainerView.addSubview(currentViewControllers[targetIndex].view)
        // 调整大小
        currentPopover.contentSize = NSSize.init(
            width: currentPopover.contentViewController!.view.frame.width,
            height: currentViewControllers[targetIndex].view.frame.height + PANEL_PADDING
        )
        // 恢复动画
        // currentPopover.animates = true
    }
}
