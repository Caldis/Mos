//
//  PreferencesAdvanceWithApplicationViewController.swift
//  Mos
//
//  Created by Caldis on 31/10/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAdvanceWithApplicationViewController: NSViewController {
    
    // Parent view
    private var parentTableView: NSTableView?
    private var parentTableRow: Int!
    // Target application
    private var currentTargetApplication: ExceptionalApplication?
    private var currentContentViewController: PreferencesAdvanceViewController?
    // UI Elements
    @IBOutlet weak var currentTargetApplicationIcon: NSImageView!
    @IBOutlet weak var currentTargetApplicationName: NSTextField!
    @IBOutlet weak var inheritGlobalSettingCheckBox: NSButton!
    
    override func viewDidLoad() {
        // 初始化显示内容
        currentTargetApplicationIcon.image = currentTargetApplication?.getIcon()
        currentTargetApplicationName.stringValue = currentTargetApplication?.getName() ?? ""
        // 读取设置
        syncViewWithOptions()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        currentContentViewController = (segue.destinationController as! PreferencesAdvanceViewController)
        if let vaildContentViewController = currentContentViewController, let validTargetApplication = currentTargetApplication {
            vaildContentViewController.currentTargetApplication = validTargetApplication
        }
    }
    
    public func updateTargetApplication(with target: ExceptionalApplication?) {
        currentTargetApplication = target
        if let vaildContentViewController = currentContentViewController, let validTargetApplication = currentTargetApplication {
            vaildContentViewController.currentTargetApplication = validTargetApplication
        }
    }
    public func updateParentData(with target: NSTableView, for row: Int) {
        parentTableView = target
        parentTableRow = row
    }
    
    // 名称
    @IBAction func currentTargetApplicationNameChange(_ sender: NSTextField) {
        let name = sender.stringValue
        if name.count > 0 {
            currentTargetApplication?.displayName = name
            if let validParentTableView = parentTableView, let validParentTableRow = parentTableRow {
                validParentTableView.reloadData(forRowIndexes: [validParentTableRow], columnIndexes: [0, 1, 2])
            }
        }
    }
    
    // 继承
    @IBAction func inheritGlobalSettingClick(_ sender: NSButton) {
        if let vaildContentViewController = currentContentViewController, let validTargetApplication = currentTargetApplication {
            validTargetApplication.inherit = sender.state.rawValue==0 ? false : true
            vaildContentViewController.syncViewWithOptions()
        }
    }
}

/**
 * 工具函数
 **/
extension PreferencesAdvanceWithApplicationViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 继承
        inheritGlobalSettingCheckBox.state = NSControl.StateValue(rawValue: (currentTargetApplication?.inherit ?? false) ? 1 : 0)
    }
}
