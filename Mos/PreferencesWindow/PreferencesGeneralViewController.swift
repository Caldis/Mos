//
//  PreferencesViewController.swift
//  Mos
//  基础选项界面
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {
    
    @IBOutlet weak var scrollSmoothCheckBox: NSButton!
    @IBOutlet weak var scrollReverseCheckBox: NSButton!
    @IBOutlet weak var launchOnLoginCheckBox: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 读取设置
        syncViewWithOptions()
    }
    
    // 平滑
    @IBAction func scrollSmoothClick(_ sender: NSButton) {
        Options.shared.basic.smooth = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 翻转
    @IBAction func scrollReverseClick(_ sender: NSButton) {
        Options.shared.basic.reverse = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 自启
    @IBAction func launchOnLoginClick(_ sender: NSButton) {
        Options.shared.basic.autoLaunch = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 同步界面与设置
    func syncViewWithOptions() {
        // 平滑
        scrollSmoothCheckBox.state = NSControl.StateValue(rawValue: Options.shared.basic.smooth ? 1 : 0)
        // 翻转
        scrollReverseCheckBox.state = NSControl.StateValue(rawValue: Options.shared.basic.reverse ? 1 : 0)
        // 自启
        launchOnLoginCheckBox.state = NSControl.StateValue(rawValue: Options.shared.basic.autoLaunch ? 1 : 0)
    }
    
}
