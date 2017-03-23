//
//  PreferencesViewController.swift
//  Mos
//  配置界面的View
//  Created by Cb on 2017/1/15.
//  Copyright © 2017年 Cb. All rights reserved.
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
        scrollSmoothCheckBox.state = ScrollCore.option.smooth ? 1 : 0
        scrollReverseCheckBox.state = ScrollCore.option.reverse ? 1 : 0
        launchOnLoginCheckBox.state = ScrollCore.option.autoLaunch ? 1 : 0
    }
    
    // 是否启用平滑滚动
    @IBAction func scrollSmoothClick(_ sender: NSButton) {
        if sender.state == 0 {
            ScrollCore.option.smooth = false
        } else {
            ScrollCore.option.smooth = true
        }
        // 保存设置
        UserDefaults.standard.set(ScrollCore.option.smooth ? "true" : "false", forKey:"smooth")
    }
    // 是否启用方向翻转
    @IBAction func scrollReverseClick(_ sender: NSButton) {
        if sender.state == 0 {
            ScrollCore.option.reverse = false
        } else {
            ScrollCore.option.reverse = true
        }
        // 保存设置
        UserDefaults.standard.set(ScrollCore.option.reverse ? "true" : "false", forKey:"reverse")
    }
    
    // 是否开机启动
    @IBAction func launchOnLoginClick(_ sender: NSButton) {
        if sender.state == 0 {
            ScrollCore.option.autoLaunch = false
            LaunchStarter.disableLaunchAtStartup()
        } else {
            ScrollCore.option.autoLaunch = true
            LaunchStarter.enableLaunchAtStartup()
        }
        
        // 保存设置
        UserDefaults.standard.set(ScrollCore.option.autoLaunch ? "true" : "false", forKey:"autoLaunch")
    }
}
