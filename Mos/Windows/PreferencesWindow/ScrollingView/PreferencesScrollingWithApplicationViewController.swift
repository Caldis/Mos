//
//  PreferencesScrollingWithApplicationViewController.swift
//  Mos
//  滚动窗口容器
//  Created by Caldis on 31/10/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class PreferencesScrollingWithApplicationViewController: NSViewController {
    
    // Parent view
    private var parentTableView: NSTableView?
    private var parentTableRow: Int!
    // Target application
    private var currentTargetApplication: Application?
    private var currentContentViewController: PreferencesScrollingViewController?
    // UI Elements
    @IBOutlet weak var currentTargetApplicationIcon: NSImageView!
    @IBOutlet weak var currentTargetApplicationName: NSTextField!
    @IBOutlet weak var inheritGlobalSettingCheckBox: NSButton!
    
    override func viewDidLoad() {
        // 初始化显示内容
        currentTargetApplicationIcon.image = currentTargetApplication?.getIcon()
        currentTargetApplicationIcon.toolTip = currentTargetApplication?.path
        currentTargetApplicationName.stringValue = currentTargetApplication?.getName() ?? ""
        // 读取设置
        syncViewWithOptions()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        currentContentViewController = (segue.destinationController as! PreferencesScrollingViewController)
        if let vaildContentViewController = currentContentViewController, let validTargetApplication = currentTargetApplication {
            vaildContentViewController.currentTargetApplication = validTargetApplication
        }
    }
    
    public func updateTargetApplication(with target: Application?) {
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
            // 同步 Logi divert: inherit=true 清除该应用所有 appScroll 占用; inherit=false 重新推送
            if validTargetApplication.inherit {
                clearAppUsage(validTargetApplication)
            } else {
                pushAppUsage(validTargetApplication)
            }
        }
    }

    // MARK: - Logi usage helpers
    private func collectAppScrollCodes(app: Application, role: ScrollRole) -> Set<UInt16> {
        let hotkey: ScrollHotkey? = {
            switch role {
            case .dash:   return app.scroll.dash
            case .toggle: return app.scroll.toggle
            case .block:  return app.scroll.block
            }
        }()
        guard !app.inherit, let h = hotkey, h.type == .mouse, LogiCenter.shared.isLogiCode(h.code) else {
            return []
        }
        return [h.code]
    }

    private func pushAppUsage(_ app: Application) {
        let key = app.path
        for role: ScrollRole in [.dash, .toggle, .block] {
            LogiCenter.shared.setUsage(source: .appScroll(key: key, role: role),
                                        codes: collectAppScrollCodes(app: app, role: role))
        }
    }

    private func clearAppUsage(_ app: Application) {
        let key = app.path
        for role: ScrollRole in [.dash, .toggle, .block] {
            LogiCenter.shared.setUsage(source: .appScroll(key: key, role: role), codes: [])
        }
    }
}

/**
 * 工具函数
 **/
extension PreferencesScrollingWithApplicationViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 继承
        inheritGlobalSettingCheckBox.state = NSControl.StateValue(rawValue: (currentTargetApplication?.inherit ?? false) ? 1 : 0)
    }
}
