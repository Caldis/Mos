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
    @IBOutlet weak var launchOnLoginCheckBox: NSButton!
    @IBOutlet weak var hideStatusBarIconCheckBox: NSButton!
    @IBOutlet weak var statusItemSecondaryClickPopUpButton: NSPopUpButton!

    override func viewDidLoad() {
        // 填充下拉框
        buildStatusItemSecondaryClickMenu()
        // 读取设置
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

    // 右键行为
    @IBAction func statusItemSecondaryClickChange(_ sender: NSPopUpButton) {
        let actions = StatusItemSecondaryClickAction.allCases
        guard actions.indices.contains(sender.indexOfSelectedItem) else { return }
        Options.shared.general.statusItemSecondaryClickAction = actions[sender.indexOfSelectedItem]
        syncViewWithOptions()
    }
}

/**
 * 设置同步
 **/
extension PreferencesGeneralViewController {
    // 下拉框选项与 StatusItemSecondaryClickAction.allCases 一一对应
    func buildStatusItemSecondaryClickMenu() {
        statusItemSecondaryClickPopUpButton.removeAllItems()
        for action in StatusItemSecondaryClickAction.allCases {
            statusItemSecondaryClickPopUpButton.addItem(withTitle: action.localizedTitle)
        }
    }
    // 同步界面与设置
    func syncViewWithOptions() {
        // 自启
        launchOnLoginCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.autoLaunch ? 1 : 0)
        // 隐藏
        hideStatusBarIconCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.hideStatusItem ? 1 : 0)
        // 右键行为
        if let index = StatusItemSecondaryClickAction.allCases.firstIndex(of: Options.shared.general.statusItemSecondaryClickAction) {
            statusItemSecondaryClickPopUpButton.selectItem(at: index)
        }
    }
}
