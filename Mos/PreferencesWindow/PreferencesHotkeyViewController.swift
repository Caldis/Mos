//
//  PreferencesHotkeyViewController.swift
//  Mos
//  热键界面
//  Created by Caldis on 2018/4/1.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesHotkeyViewController: NSViewController {

    @IBOutlet weak var shiftKeyPopUpButton: NSPopUpButton!
    @IBOutlet weak var disableKeyPopUpButton: NSPopUpButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 读取设置
        syncViewWithOptions()
    }
    
    // 转换
    @IBAction func shiftKeyPopUpButtonChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        Options.shared.hotkey.shift = index>1 ? Utils.modifierKeys[index-2] : 0
    }

    // 禁用
    @IBAction func disableKeyPopUpButtonChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        Options.shared.hotkey.block = index>1 ? Utils.modifierKeys[index-2] : 0
    }
    
    // 同步界面与设置
    func syncViewWithOptions() {
        // 转换
        if let index = Utils.modifierKeys.index(of: Options.shared.hotkey.shift) {
            shiftKeyPopUpButton.selectItem(at: index+2)
        } else {
            shiftKeyPopUpButton.selectItem(at: 0)
        }
        // 禁用
        if let index = Utils.modifierKeys.index(of: Options.shared.hotkey.block) {
            disableKeyPopUpButton.selectItem(at: index+2)
        } else {
            disableKeyPopUpButton.selectItem(at: 0)
        }
    }
    
}
