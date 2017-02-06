//
//  PreferencesViewController.swift
//  Mos
//  配置界面的View
//  Created by Cb on 2017/1/15.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {
    
    // Checkbox
    @IBOutlet weak var scrollSmoothCheckBox: NSButton!
    @IBOutlet weak var scrollReverseCheckBox: NSButton!
    // Shortcut
    // var kShortCut: MASShortcut!
    // @IBOutlet weak var scrollSmoothShortcutRecoder: MASShortcutView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 恢复一下设置
        scrollSmoothCheckBox.state = ScrollCore.option.smooth ? 1 : 0
        scrollReverseCheckBox.state = ScrollCore.option.reverse ? 1 : 0
        // 初始化Shortcut
//        scrollSmoothShortcutRecoder.shortcutValueChange = {
//            sender in
//            if let shortCutKey = self.scrollSmoothShortcutRecoder.shortcutValue {
//                self.kShortCut = shortCutKey
//                MASShortcutMonitor.shared().register(self.scrollSmoothShortcutRecoder.shortcutValue, withAction: {
//                    print("\(shortCutKey) shortcut handler")
//                })
//            }
//        }
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
}
