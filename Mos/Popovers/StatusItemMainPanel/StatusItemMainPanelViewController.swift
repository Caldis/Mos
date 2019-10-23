//
//  StatusItemMainPanel.swift
//  Mos
//
//  Created by Caldis on 2019/10/11.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Foundation

class StatusItemMainPanelViewController: NSViewController {

    // 常量
    let COLLAPSE_PADDING = CGFloat(72.0)
    let EXPANSION_PADDING = CGFloat(372.0)
    // 引用
    // 面板展开
    var expansionPanelIsOpen = false {
        willSet {
            newValue ? expansion() : collapse()
        }
    }
    // 控件
    @IBOutlet weak var expansionIndicatorPlus: NSImageView!
    @IBOutlet weak var expansionIndicatorMinus: NSImageView!
    
    // 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置界面大小
        view.frame.size = NSSize(
            width: view.frame.size.width,
            height: COLLAPSE_PADDING
        )
        // 设置按钮状态
        expansionIndicatorMinus.layer?.transform = CATransform3DMakeRotation(-180.0, 0, 0, 1)
        expansionIndicatorMinus.alphaValue = 0
    }
    
    // 切换按钮点击
    @IBAction func expansionToggleClick(_ sender: NSButton) {
        expansionPanelIsOpen = !expansionPanelIsOpen
    }
}

/**
 * 面板展开控制
 **/
extension StatusItemMainPanelViewController {
    
    func syncParentControllerSize() {
        // 父容器尺寸
        let statusItemPopover = PopoverManager.shared.get(withIdentifier: POPOVER_IDENTIFIER.statusItemPopoverViewController).contentViewController
        if let statusItemPopoverViewController = statusItemPopover as? StatusItemPopoverViewController {
            statusItemPopoverViewController.syncSizeWithContent()
        }
    }
    
    func expansion() {
        Utils.groupAnimatorContainer({(context) in
            // 图标
            expansionIndicatorPlus.animator().alphaValue = 0
            expansionIndicatorPlus.animator().layer?.transform = CATransform3DMakeRotation(180.0, 0, 0, 1)
            expansionIndicatorMinus.animator().alphaValue = 0.75
            expansionIndicatorMinus.animator().layer?.transform = CATransform3DMakeRotation(0.0, 0, 0, 1)
            // 容器尺寸
            view.frame.size = NSSize(width: view.frame.size.width, height: EXPANSION_PADDING)
            // 父容器尺寸
            syncParentControllerSize()
        }, headHandler: {() in
            self.expansionIndicatorPlus.layer?.position = CGPoint(x: self.expansionIndicatorPlus.layer!.frame.midX, y: self.expansionIndicatorPlus.layer!.frame.midY)
            self.expansionIndicatorPlus.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            self.expansionIndicatorMinus.layer?.position = CGPoint(x: self.expansionIndicatorMinus.layer!.frame.midX, y: self.expansionIndicatorMinus.layer!.frame.midY)
            self.expansionIndicatorMinus.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        })
    }
    func collapse() {
        Utils.groupAnimatorContainer({(context) in
            // 图标
            expansionIndicatorPlus.animator().alphaValue = 0.75
            expansionIndicatorPlus.animator().layer?.transform = CATransform3DMakeRotation(0.0, 0, 0, 1)
            expansionIndicatorMinus.animator().alphaValue = 0
            expansionIndicatorMinus.animator().layer?.transform = CATransform3DMakeRotation(-180.0, 0, 0, 1)
            // 容器尺寸
            view.frame.size = NSSize(width: view.frame.size.width, height: COLLAPSE_PADDING)
            // 父容器尺寸
            syncParentControllerSize()
        }, headHandler: {() in
            self.expansionIndicatorPlus.layer?.position = CGPoint(x: self.expansionIndicatorPlus.layer!.frame.midX, y: self.expansionIndicatorPlus.layer!.frame.midY)
            self.expansionIndicatorPlus.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            self.expansionIndicatorMinus.layer?.position = CGPoint(x: self.expansionIndicatorMinus.layer!.frame.midX, y: self.expansionIndicatorMinus.layer!.frame.midY)
            self.expansionIndicatorMinus.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        })
    }
    
}
