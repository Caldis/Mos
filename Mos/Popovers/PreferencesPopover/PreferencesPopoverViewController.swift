//
//  PreferencesPopoverController.swift
//  Mos
//  状态栏弹出
//  Created by Caldis on 2018/12/29.
//  Copyright © 2018 Caldis. All rights reserved.
//

import Cocoa

let PANEL_IDENTIFIER = (
    general: "general",
    advanced: "advanced",
    exception: "exception"
)
let PANEL_IDENTIFIER_LIST = [
    PANEL_IDENTIFIER.general,
    PANEL_IDENTIFIER.advanced,
    PANEL_IDENTIFIER.exception,
]
let PANEL_PADDING = CGFloat(84.0)

class PreferencesPopoverViewController: NSViewController {
    
    // 点击监听
    var clickEventMonitor: EventMonitor?
    // 引用
    @IBOutlet weak var preferencesTabSegmentControl: NSSegmentedControl!
    @IBOutlet weak var preferencesContainerView: NSView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置TAB分页
        for panelIdentifier in PANEL_IDENTIFIER_LIST {
            if let targetPreferencesViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: panelIdentifier) as NSViewController? {
                targetPreferencesViewController.view.alphaValue = 0.0
                preferencesContainerView.addSubview(targetPreferencesViewController.view)
            }
        }
        // 显示第一个TAB分页
        showTargetPanel(with: 0)
        // 激活窗口 (PopoverManager 中的激活在部分情况下不生效)
        NSApp.activate(ignoringOtherApps: true)
    }
    override func viewWillAppear() {
        // 监听鼠标点击外部
        clickEventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: hidePopover)
        clickEventMonitor?.start()
    }
    
    @IBAction func preferencesTabSegmentControlSelected(_ sender: NSSegmentedCell) {
        showTargetPanel(with: sender.selectedSegment)
    }
    
    
}

/**
 * 面板控制
 **/
extension PreferencesPopoverViewController {
    
    //  隐藏Popover
    func hidePopover(_:NSEvent?) {
        PopoverManager.shared.hidePopover(withIdentifier: PopoverManager.shared.identifier.preferencesPopoverController)
        clickEventMonitor?.stop()
    }
    
    func showTargetPanel(with targetIndex: Int) {
        // 隐藏原有 subView
        for subView in preferencesContainerView.subviews {
            subView.alphaValue = 0.0
        }
        // 显示新 View
        let targetView = preferencesContainerView.subviews[targetIndex]
        let currentPopover = PopoverManager.shared.refs[PopoverManager.shared.identifier.preferencesPopoverController]!
        let currentPopoverFrame = currentPopover.contentViewController!.view.frame
        let heightTarget = targetView.frame.height
        if #available(OSX 10.12, *) {
            NSAnimationContext.runAnimationGroup({ (context) in
                context.duration = 1.0
                preferencesContainerView.subviews[targetIndex].animator().alphaValue = 1.0
            })
        } else {
            preferencesContainerView.subviews[targetIndex].alphaValue = 1.0
        }
        currentPopover.contentSize = NSSize.init(width: currentPopoverFrame.width, height: heightTarget + PANEL_PADDING)
    }
}
