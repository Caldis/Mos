//
//  IntroductionViewController.swift
//  Mos
//
//  Created by Caldis on 15/11/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class IntroductionViewController: NSViewController {
    
    // 子界面
    var currentViewIndex = 0
    let viewList = [
        Utils.instantiateControllerFromStoryboard(withIdentifier: VIEW_IDENTIFIER.introductionStepOneViewController) as NSViewController,
        Utils.instantiateControllerFromStoryboard(withIdentifier: VIEW_IDENTIFIER.introductionStepTwoViewController) as NSViewController,
        Utils.instantiateControllerFromStoryboard(withIdentifier: VIEW_IDENTIFIER.introductionStepThreeViewController) as NSViewController
    ]
    // 辅助功能权限检查器
    var accessibilityPermissionsCheckerTimer: Timer?
    // 按钮文字
    var nextLabelI18NText: String!
    
    // UI Elements
    @IBOutlet weak var containerView: NSView!
    @IBOutlet weak var prevButton: NSButton!
    @IBOutlet weak var prevButtonLabel: NSTextField!
    @IBOutlet weak var nextButton: NSButton!
    @IBOutlet weak var nextButtonLabel: NSTextField!
    
    override func viewDidLoad() {
        // 初始化控制器
        for viewController in viewList { addChild(viewController) }
        containerView.addSubview(children[0].view)
        // 初始化文字
        nextLabelI18NText = nextButtonLabel.stringValue
        // 启动定时器检测权限, 当拥有授权时启动滚动处理
        accessibilityPermissionsCheckerTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(accessibilityPermissionsChecker(_:)),
            userInfo: nil,
            repeats: true
        )
    }
    override func viewWillDisappear() {
        accessibilityPermissionsCheckerTimer?.invalidate()
   }
    
    @IBAction func prevButtonClick(_ sender: NSButton) {
        switchToPage(to: currentViewIndex-1)
    }
    @IBAction func nextButtonClick(_ sender: NSButton) {
        if currentViewIndex == viewList.count-1 {
            // 最后一页请求权限
            Utils.requireAccessibilityPermissions()
        } else {
            switchToPage(to: currentViewIndex+1)
        }
    }
}

/*
 * 权限检测
 */
extension IntroductionViewController {
    // 检查是否有访问 accessibility 权限, 并设置对应按钮
    @objc func accessibilityPermissionsChecker(_ timer: Timer) {
        // 如果有权限
        if AXIsProcessTrusted() {
            // 关闭检测
            accessibilityPermissionsCheckerTimer?.invalidate()
            // 关闭窗口
            view.window?.close()
        }
    }
}

/*
 * 界面切换
 */
extension IntroductionViewController {
    // 翻页
    func switchToPage(to targetViewIndex: Int) {
        if targetViewIndex>=0 && targetViewIndex<viewList.count {
            // 切换按钮可见性
            if targetViewIndex == 0 {
                prevButton.isHidden = true
                prevButtonLabel.isHidden = true
                nextButton.isHidden = false
                nextButtonLabel.isHidden = false
            } else if targetViewIndex == viewList.count {
                prevButton.isHidden = false
                prevButtonLabel.isHidden = false
                nextButton.isHidden = true
                nextButtonLabel.isHidden = true
            } else {
                prevButton.isHidden = false
                prevButtonLabel.isHidden = false
                nextButton.isHidden = false
                nextButtonLabel.isHidden = false
            }
            // 切换页面
            let currentViewController = viewList[currentViewIndex]
            let targetViewController = viewList[targetViewIndex]
            if targetViewIndex < currentViewIndex {
                transition(from: currentViewController, to: targetViewController, options: .slideRight, completionHandler: nil)
            } else {
                transition(from: currentViewController, to: targetViewController, options: .slideLeft, completionHandler: nil)
            }
            // 更新文本
            if targetViewIndex == viewList.count-1 {
                nextButtonLabel.stringValue = i18n.allowToAccess
            } else {
                nextButtonLabel.stringValue = nextLabelI18NText
            }
            // 更新引用
            currentViewIndex = targetViewIndex
        }
    }
}
