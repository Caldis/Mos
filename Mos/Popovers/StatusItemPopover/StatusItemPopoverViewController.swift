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
    var currentContentStack = [NSViewController]()
    // 控件
    @IBOutlet var menuControl: NSMenu!
    @IBOutlet weak var contentView: NSView!
    
    // 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        // 获取 Popover
        currentPopover = PopoverManager.shared.refs[POPOVER_IDENTIFIER.statusItemPopoverViewController]!
        currentPopover.delegate = self
        // 初始化内容
        let contentViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: POPOVER_IDENTIFIER.statusItemMainPanelViewController) as NSViewController
        addChild(contentViewController)
        contentView.addSubview(contentViewController.view)
    }
    override func viewWillAppear() {
        // 初始化大小
//        syncSizeWithContent(animate: false)
        // 监听关闭
        clickEventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: hidePopover)
    }
    
    // 按钮点击
    @IBAction func titleBackButtonClick(_ sender: NSButton) {
        popContentView()
    }
    @IBAction func monitorButtonClick(_ sender: NSButton) {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController, withTitle: "")
    }
    @IBAction func settingButtonClick(_ sender: NSButton) {
        let targetPosition = NSPoint(x: sender.frame.origin.x, y: sender.frame.origin.y + sender.frame.height + -25)
        menuControl.popUp(positioning: nil, at: targetPosition, in: sender.superview)
    }
    @IBAction func menuControlPreferencesButtonClick(_ sender: NSMenuItem) {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController, withTitle: i18n.preferences)
    }
    @IBAction func menuControlQuitButtonClick(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}

/**
 * 面板行为控制
 **/
extension StatusItemPopoverViewController: NSPopoverDelegate {
    
    // NSPopoverDelegate
    // 允许脱离
    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return true
    }
    
    // 同步尺寸
    func syncSizeWithContent(animate: Bool = true) {
        
        if let currentContentView = contentView.subviews.last {
            print(currentContentView.frame.size)
        }
//        if (animate) {
//            Utils.groupAnimatorContainer({(context) in
//                if let currentContentView = contentView.subviews.last {
//                    currentPopover.contentSize = NSSize(
//                        width: currentPopover.contentSize.width,
//                        height: currentContentView.frame.size.height + PANEL_PADDING
//                    )
//                }
//            })
//        } else {
//            if let currentContentView = contentView.subviews.last {
//                currentPopover.contentSize = NSSize(
//                    width: currentPopover.contentSize.width,
//                    height: currentContentView.frame.size.height + PANEL_PADDING
//                )
//            }
//        }
    }
    
    // 切换到设置
    func segueToSetting(with application: ExceptionalApplication) {
        // 设置当前应用
//        PreferencesAdvanceViewController.sharedTargetApplication = application
        // 显示设置界面
        pushContentView(with: PANEL_IDENTIFIER.advancedWithNavigation)
    }
    
    // 隐藏
    func hidePopover(_:NSEvent?) {
        PopoverManager.shared.hidePopover(withIdentifier: POPOVER_IDENTIFIER.statusItemPopoverViewController)
        clickEventMonitor?.stop()
    }
    
}

/**
 * 界面导航
 **/
extension StatusItemPopoverViewController {
    
    // 追加
    func appendContentViewController(with viewController: NSViewController, relatedTo currViewController: NSViewController?) {
        // 设置初始样式
        viewController.view.frame.origin = NSPoint(x: currViewController?.view.frame.size.width ?? 0, y: PANEL_PADDING)
        viewController.view.alphaValue = 0.5
        // 追加 ViewController
        addChild(viewController)
        // 追加 View
        view.addSubview(viewController.view)
        currentContentStack.append(viewController)
    }
    // 清除:指定
    func removeTargetContentViewController(with viewController: NSViewController) {
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
        if let targetIndex = currentContentStack.lastIndex(of: viewController) {
            currentContentStack.remove(at: targetIndex)
        }
    }
    // 清除:末尾
    func removeLastContentViewController() {
        currentContentStack.last?.view.removeFromSuperview()
        children.last?.removeFromParent()
        currentContentStack.removeLast()
    }
    
    // 前进
    func pushContentView(with identifier: String, sync: Bool = true) {
        // 获取目标页
        let currContentViewController = currentContentStack.last
        let nextContentViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier) as NSViewController
        // 追加页面
//        appendContentViewController(with: nextContentViewController, relatedTo: currContentViewController)
        transition(from: currContentViewController!, to: nextContentViewController, options: .slideLeft, completionHandler: nil)
        // 调整大小
        Utils.groupAnimatorContainer({(context) in
            // 设置样式
            segueToNextContentView(curr: currContentViewController, next: nextContentViewController)
        })
    }
    func segueToNextContentView(curr currController: NSViewController?, next nextController: NSViewController) {
        // 设置下个尺寸
        nextController.view.animator().alphaValue = 1
        nextController.view.animator().frame.origin = NSPoint(x: 0, y: PANEL_PADDING)
        // 设置当前尺寸
        if let currView = currController?.view {
            currView.animator().alphaValue = 0.5
            currView.animator().frame.origin = NSPoint(x: -currView.frame.size.width/3, y: PANEL_PADDING)
        }
    }
    
    // 后退
    func popContentView(sync: Bool = true) {
        // 获取目标页
        let currContentViewController = currentContentStack.last!
        let currContentViewControllerIndex = currentContentStack.lastIndex(of: currContentViewController) ?? 1
        // 仅当当前页面堆栈大于 0 时允许后退
        if currContentViewControllerIndex > 0 {
            let prevContentViewControllerIndex = currentContentStack.index(before: currContentViewControllerIndex)
            let prevContentViewController = currentContentStack[prevContentViewControllerIndex]
            // 调整大小
            Utils.groupAnimatorContainer({(context) in
                // 触发转场
                segueToPrevContentView(curr: currContentViewController, prev: prevContentViewController)
            }, completionHandler: { () in
                // 清除数据
                self.removeTargetContentViewController(with: currContentViewController)
            })
        }
    }
    func segueToPrevContentView(curr currController: NSViewController, prev prevController: NSViewController) {
        // 设置上个尺寸
        prevController.view.animator().alphaValue = 1
        prevController.view.animator().frame.origin = NSPoint(x: 0, y: PANEL_PADDING)
        // 设置当前尺寸
        currController.view.animator().alphaValue = 0.5
        currController.view.animator().frame.origin = NSPoint(x: currController.view.frame.size.width, y: PANEL_PADDING)
    }
}
