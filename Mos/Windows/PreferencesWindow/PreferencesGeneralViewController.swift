//
//  PreferencesViewController.swift
//  Mos
//  基础选项界面
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {
    
    // UI Elements
    @IBOutlet weak var scrollSmoothCheckBox: NSButton!
    @IBOutlet weak var scrollReverseCheckBox: NSButton!
    @IBOutlet weak var launchOnLoginCheckBox: NSButton!
    @IBOutlet weak var hideStatusBarIconCheckBox: NSButton!
    
    override func viewDidLoad() {
        // 读取设置
        syncViewWithOptions()
    }
    
    // 平滑
    @IBAction func scrollSmoothClick(_ sender: NSButton) {
        Options.shared.scrollBasic.smooth = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 翻转
    @IBAction func scrollReverseClick(_ sender: NSButton) {
        Options.shared.scrollBasic.reverse = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 自启
    @IBAction func launchOnLoginClick(_ sender: NSButton) {
        Options.shared.general.autoLaunch = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 隐藏
    @IBAction func hideStatusBarIconClick(_ sender: NSButton) {
        Options.shared.general.hideStatusItem = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
}

/**
 * 设置同步
 **/
extension PreferencesGeneralViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 平滑
        scrollSmoothCheckBox.state = NSControl.StateValue(rawValue: Options.shared.scrollBasic.smooth ? 1 : 0)
        // 翻转
        scrollReverseCheckBox.state = NSControl.StateValue(rawValue: Options.shared.scrollBasic.reverse ? 1 : 0)
        // 自启
        launchOnLoginCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.autoLaunch ? 1 : 0)
        // 隐藏
        hideStatusBarIconCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.hideStatusItem ? 1 : 0)
    }
}
