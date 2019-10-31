//
//  PreferencesAdvanceWithApplicationViewController.swift
//  Mos
//
//  Created by Caldis on 31/10/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAdvanceWithApplicationViewController: NSViewController {
    
    // Target application
    var currentTargetApplication: ExceptionalApplication!
    var currentContentViewController: PreferencesAdvanceViewController!
    // UI Elements
    @IBOutlet weak var currentTargetApplicationIcon: NSImageView!
    @IBOutlet weak var currentTargetApplicationName: NSTextField!
    @IBOutlet weak var inheritGlobalSettingCheckBox: NSButton!
    
    override func viewDidLoad() {
        // 初始化显示内容
        currentTargetApplicationIcon.image = currentTargetApplication.getIcon()
        currentTargetApplicationName.stringValue = currentTargetApplication.getName()
        // 读取设置
        syncViewWithOptions()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        currentContentViewController = (segue.destinationController as! PreferencesAdvanceViewController)
        currentContentViewController.currentTargetApplication = currentTargetApplication
    }
    
    // 继承
    @IBAction func inheritGlobalSettingClick(_ sender: NSButton) {
        currentTargetApplication.inherit = sender.state.rawValue==0 ? false : true
        currentContentViewController.syncViewWithOptions()
    }
}

/**
 * 工具函数
 **/
extension PreferencesAdvanceWithApplicationViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 继承
        inheritGlobalSettingCheckBox.state = NSControl.StateValue(rawValue: currentTargetApplication.inherit ? 1 : 0)
    }
}
