//
//  IntroductionViewController.swift
//  Mos
//
//  Created by Caldis on 15/11/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class IntroductionViewController: NSViewController {

    // 辅助功能权限检查器
    var accessibilityPermissionsCheckerTimer: Timer?
    // 帮助弹窗
    var isViewFirstActive = true
    var isHelpPopoverShowed = false
    // 是否从偏好设置手动打开的标识
    var isManuallyOpened = false
    
    // 设置手动打开标识的方法
    func setManuallyOpened(_ manually: Bool) {
        isManuallyOpened = manually
        // 如果是手动打开，停止现有的定时器
        if manually {
            accessibilityPermissionsCheckerTimer?.invalidate()
            accessibilityPermissionsCheckerTimer = nil
        }
    }
    @IBOutlet weak var helpButton: NSButton!
    @IBOutlet weak var helpDragAppArrow: NSImageView!
    @IBOutlet weak var helpDragAppSparkle: NSImageView!
    
    // UI Elements
    @IBOutlet weak var authButton: NSButton!
    
    override func viewDidLoad() {
        // 初始化文字
        authButton.title = i18n.allowToAccess
        // 只有在非手动打开的情况下才启动权限检测定时器
        if !isManuallyOpened {
            accessibilityPermissionsCheckerTimer = Timer.scheduledTimer(
                timeInterval: 1.0,
                target: self,
                selector: #selector(accessibilityPermissionsChecker(_:)),
                userInfo: nil,
                repeats: true
            )
        }
        // 检查获得焦点
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    override func viewWillDisappear() {
        NotificationCenter.default.removeObserver(self)
        accessibilityPermissionsCheckerTimer?.invalidate()
    }
    
    @IBAction func handleHelpButtonClick(_ sender: Any) {
        helpDragAppArrow.isHidden = false
        helpDragAppSparkle.isHidden = false
    }
    
}

/*
 * 帮助界面处理
 */
extension IntroductionViewController {
    // 切换回帮助视图 (用户没授权成功)
    @objc private func handleAppActive() {
        // Guard: skip first
        if (isViewFirstActive) {
            isViewFirstActive = false
            return
        }
        // Guard: 如果显示过就不再主动触发显示了
        if (isHelpPopoverShowed) { return }
        // 显示帮助弹窗
        isHelpPopoverShowed = true
        helpDragAppArrow.isHidden = false
        helpDragAppSparkle.isHidden = false
        helpButton.performClick(self)
    }
}

/*
 * 权限处理
 */
extension IntroductionViewController {
    // 检查是否有访问 accessibility 权限, 并设置对应按钮
    @objc func accessibilityPermissionsChecker(_ timer: Timer) {
        // 如果有权限
        if AXIsProcessTrusted() {
            // 关闭检测
            accessibilityPermissionsCheckerTimer?.invalidate()
            // 只有在非手动打开的情况下才关闭窗口
            if !isManuallyOpened {
                view.window?.close()
            }
        }
    }
    // 请求获取权限
    @IBAction func authButtonClick(_ sender: NSButton) {
        Utils.requireAccessibilityPermissions()
    }
}
