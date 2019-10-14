//
//  StatusItemMainPanel.swift
//  Mos
//
//  Created by Caldis on 2019/10/11.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Foundation

class StatusItemMainPanelViewController: NSViewController {

    // 引用
    // 面板展开
//    var expansionPanelIsOpen = false {
//        willSet {
//            newValue ? expansion() : collapse()
//        }
//    }
    // 控件
    @IBOutlet weak var expansionIndicatorPlus: NSImageView!
    @IBOutlet weak var expansionIndicatorMinus: NSImageView!
    
    // 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置状态
//        expansionIndicatorMinus.layer?.transform = CATransform3DMakeRotation(-180.0, 0, 0, 1)
//        expansionIndicatorMinus.alphaValue = 0
    }
    
    // 按钮点击
    @IBAction func expansionOverlayClick(_ sender: NSButton) {
//        expansionPanelIsOpen = !expansionPanelIsOpen
    }
}

/**
 * 面板展开控制
 **/
extension StatusItemPopoverViewController {
    
//    func expansion() {
//        Utils.groupAnimatorContainer({(context) in
//            expansionIndicatorPlus.animator().alphaValue = 0
//            expansionIndicatorPlus.animator().layer?.transform = CATransform3DMakeRotation(180.0, 0, 0, 1)
//            expansionIndicatorMinus.animator().alphaValue = 0.75
//            expansionIndicatorMinus.animator().layer?.transform = CATransform3DMakeRotation(0.0, 0, 0, 1)
//        }, headHandler: {() in
//            self.expansionIndicatorPlus.layer?.position = CGPoint(x: self.expansionIndicatorPlus.layer!.frame.midX, y: self.expansionIndicatorPlus.layer!.frame.midY)
//            self.expansionIndicatorPlus.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
//            self.expansionIndicatorMinus.layer?.position = CGPoint(x: self.expansionIndicatorMinus.layer!.frame.midX, y: self.expansionIndicatorMinus.layer!.frame.midY)
//            self.expansionIndicatorMinus.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
//        })
//        setControllerToFullSize()
//    }
//    func collapse() {
//        Utils.groupAnimatorContainer({(context) in
//            expansionIndicatorPlus.animator().alphaValue = 0.75
//            expansionIndicatorPlus.animator().layer?.transform = CATransform3DMakeRotation(0.0, 0, 0, 1)
//            expansionIndicatorMinus.animator().alphaValue = 0
//            expansionIndicatorMinus.animator().layer?.transform = CATransform3DMakeRotation(-180.0, 0, 0, 1)
//        }, headHandler: {() in
//            self.expansionIndicatorPlus.layer?.position = CGPoint(x: self.expansionIndicatorPlus.layer!.frame.midX, y: self.expansionIndicatorPlus.layer!.frame.midY)
//            self.expansionIndicatorPlus.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
//            self.expansionIndicatorMinus.layer?.position = CGPoint(x: self.expansionIndicatorMinus.layer!.frame.midX, y: self.expansionIndicatorMinus.layer!.frame.midY)
//            self.expansionIndicatorMinus.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
//        })
//        setControllerToCollapseSize()
//    }
    
}
