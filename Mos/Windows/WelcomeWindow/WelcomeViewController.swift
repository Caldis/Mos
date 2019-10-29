//
//  WelcomeViewController.swift
//  Mos
//  欢迎界面的 View
//  Created by Caldis on 2018/7/9.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class WelcomeViewController: NSViewController {
    
    @IBOutlet weak var versionLabel: NSTextField!
    @IBOutlet weak var allowToAccessButton: NSButton!
    @IBOutlet weak var beginSmoothButton: NSButton!
    
    // 检查器
    var checkerTimer: Timer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 获取版本号
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!
        versionLabel.stringValue = "\(i18n.currentVersion) : \(version as! String)"
    }
    override func viewWillAppear() {
        // 启动定时器检测权限, 当拥有授权时启动滚动处理
        checkerTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(accessibilityPermissionsChecker(_:)),
            userInfo: nil,
            repeats: true
        )
    }
    override func viewWillDisappear() {
        checkerTimer.invalidate()
    }
    
    @IBAction func allowToAccessButtonClick(_ sender: NSButton) {
        Utils.requireAccessibilityPermissions()
    }
    @IBAction func beginSmoothButtonClick(_ sender: NSButton) {
        WindowManager.shared.refs[WINDOW_IDENTIFIER.welcomeWindowController]?.close()
    }
    

    // 检查是否有访问 accessibility 权限, 并设置对应按钮
    @objc func accessibilityPermissionsChecker(_ timer: Timer) {
        if AXIsProcessTrusted() {
            // 如果有权限
            allowToAccessButton.title = i18n.done
            allowToAccessButton.isEnabled = false
            beginSmoothButton.isEnabled = true
        } else {
            // 如果没权限
            allowToAccessButton.title = i18n.allowToAccess
            allowToAccessButton.isEnabled = true
            beginSmoothButton.isEnabled = false
        }
    }
    
}
