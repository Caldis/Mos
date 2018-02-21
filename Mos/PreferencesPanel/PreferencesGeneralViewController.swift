//
//  PreferencesViewController.swift
//  Mos
//  基础选项界面
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa
import ServiceManagement

class PreferencesGeneralViewController: NSViewController {
    
    // Checkbox
    @IBOutlet weak var scrollSmoothCheckBox: NSButton!
    @IBOutlet weak var scrollReverseCheckBox: NSButton!
    @IBOutlet weak var launchOnLoginCheckBox: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 恢复一下设置
        scrollSmoothCheckBox.state = NSControl.StateValue(rawValue: Options.shared.current.basic.smooth ? 1 : 0)
        scrollReverseCheckBox.state = NSControl.StateValue(rawValue: Options.shared.current.basic.reverse ? 1 : 0)
        launchOnLoginCheckBox.state = NSControl.StateValue(rawValue:Options.shared.current.basic.autoLaunch ? 1 : 0)
    }
    
    // 是否启用平滑滚动
    @IBAction func scrollSmoothClick(_ sender: NSButton) {
        if sender.state.rawValue == 0 {
            Options.shared.current.basic.smooth = false
        } else {
            Options.shared.current.basic.smooth = true
        }
        // 保存设置
        UserDefaults.standard.set(Options.shared.current.basic.smooth ? "true" : "false", forKey:"smooth")
    }
    // 是否启用方向翻转
    @IBAction func scrollReverseClick(_ sender: NSButton) {
        if sender.state.rawValue == 0 {
            Options.shared.current.basic.reverse = false
        } else {
            Options.shared.current.basic.reverse = true
        }
        // 保存设置
        UserDefaults.standard.set(Options.shared.current.basic.reverse ? "true" : "false", forKey:"reverse")
    }
    // 是否开机启动
    @IBAction func launchOnLoginClick(_ sender: NSButton) {
        if sender.state.rawValue == 0 {
            Options.shared.current.basic.autoLaunch = false
            LaunchStarter.disableLaunchAtStartup()
        } else {
            Options.shared.current.basic.autoLaunch = true
            LaunchStarter.enableLaunchAtStartup()
        }
        // 保存设置
        UserDefaults.standard.set(Options.shared.current.basic.autoLaunch ? "true" : "false", forKey:"autoLaunch")
    }
}
