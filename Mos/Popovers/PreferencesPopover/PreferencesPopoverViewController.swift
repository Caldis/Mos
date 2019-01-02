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

class PreferencesPopoverViewController: NSViewController {
    
    // 点击监听
    var clickEventMonitor: EventMonitor?
    
    // 引用
    @IBOutlet weak var preferencesTabSegmentControl: NSSegmentedControl!
    @IBOutlet weak var preferencesContainerView: NSView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 监听鼠标点击外部
        clickEventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: hidePopover)
        clickEventMonitor?.start()
        // 设置窗口
        let currentPreferencesViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.general) as NSViewController
        preferencesContainerView.addSubview(currentPreferencesViewController.view)
        // 激活窗口 (PopoverManager中的激活在部分情况下不生效)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func preferencesTabSegmentControlSelected(_ sender: NSSegmentedCell) {
        // 移除原有 subView
        for subView in preferencesContainerView.subviews {
            subView.removeFromSuperview()
        }
        // 切换到新 View
        let index = sender.selectedSegment
        let currentPreferencesViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER_LIST[index]) as NSViewController
        preferencesContainerView.addSubview(currentPreferencesViewController.view)
    }
}

/**
 * 面板控制
 **/
extension PreferencesPopoverViewController {
    func hidePopover(_:NSEvent?) {
        PopoverManager.shared.hidePopover(withIdentifier: PopoverManager.shared.identifier.preferencesPopoverController)
        clickEventMonitor?.stop()
    }
}
