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
    var panelViewControllers = [NSViewController]()
    @IBOutlet weak var preferencesTabSegmentControl: NSSegmentedControl!
    @IBOutlet weak var preferencesContainerView: NSView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 初始化分页
        for identifier in PANEL_IDENTIFIER_LIST {
            panelViewControllers.append(Utils.instantiateControllerFromStoryboard(withIdentifier: identifier)!)
        }
        // 显示第一个TAB分页
        showTargetPanel(with: 0)
    }
    override func viewWillAppear() {
        // 监听鼠标点击外部
        clickEventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: hidePopover)
        // 激活窗口
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func preferencesTabSegmentControlSelected(_ sender: NSSegmentedCell) {
        showTargetPanel(with: sender.selectedSegment)
    }
    
}

/**
 * 面板控制
 **/
extension PreferencesPopoverViewController {
    
    //  隐藏 Popover
    func hidePopover(_:NSEvent?) {
        PopoverManager.shared.hidePopover(withIdentifier: PopoverManager.shared.identifier.preferencesPopoverController)
        clickEventMonitor?.stop()
    }
    
    // 切换到特定分页
    func showTargetPanel(with targetIndex: Int) {
        // 删除原有的
        for subView in preferencesContainerView.subviews {
            subView.removeFromSuperview()
        }
        // 添加新的
        let targetView = panelViewControllers[targetIndex].view
        // 插入
        preferencesContainerView.addSubview(targetView)
        // 调整大小
        let currentPopover = PopoverManager.shared.refs[PopoverManager.shared.identifier.preferencesPopoverController]!
        currentPopover.contentSize = NSSize.init(width: currentPopover.contentViewController!.view.frame.width, height: targetView.frame.height + PANEL_PADDING)
    }
}
