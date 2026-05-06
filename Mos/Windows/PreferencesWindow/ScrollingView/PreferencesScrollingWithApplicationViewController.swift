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
    private var ignoreScrollSourceCheckBox: NSButton?
    
    override func viewDidLoad() {
        // 初始化显示内容
        currentTargetApplicationIcon.image = currentTargetApplication?.getIcon()
        currentTargetApplicationIcon.toolTip = currentTargetApplication?.path
        currentTargetApplicationName.stringValue = currentTargetApplication?.getName() ?? ""
        currentTargetApplicationName.toolTip = currentTargetApplication?.path
        configureIgnoreScrollSourceCheckBox()
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
        if isViewLoaded {
            syncViewWithOptions()
        }
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
                let columnIndexes = IndexSet(integersIn: 0..<validParentTableView.numberOfColumns)
                validParentTableView.reloadData(forRowIndexes: [validParentTableRow], columnIndexes: columnIndexes)
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

    @objc func ignoreScrollSourceClick(_ sender: NSButton) {
        guard let validTargetApplication = currentTargetApplication else { return }
        validTargetApplication.ignoreAsScrollSource = sender.state == .on
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
    private func configureIgnoreScrollSourceCheckBox() {
        guard let headerContentView = inheritGlobalSettingCheckBox.superview,
              let headerBox = headerContentView.superview else { return }

        let checkBox = NSButton(
            checkboxWithTitle: NSLocalizedString("Ignore Scroll Source", comment: "Per-application option for ignoring scroll events emitted by this app"),
            target: self,
            action: #selector(ignoreScrollSourceClick)
        )
        checkBox.controlSize = .small
        checkBox.font = NSFont.menuFont(ofSize: 11)
        checkBox.imagePosition = .imageRight
        checkBox.translatesAutoresizingMaskIntoConstraints = false
        checkBox.toolTip = NSLocalizedString("Pass through scroll events emitted by this app without Mos smoothing", comment: "Tooltip for ignore scroll source checkbox")
        headerContentView.addSubview(checkBox)
        ignoreScrollSourceCheckBox = checkBox
        headerBox.constraints
            .filter { $0.firstAttribute == .height }
            .forEach { $0.constant = max($0.constant, 58) }

        let nameWidth = currentTargetApplicationName.widthAnchor.constraint(lessThanOrEqualToConstant: 150)
        nameWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            nameWidth,
            checkBox.leadingAnchor.constraint(equalTo: inheritGlobalSettingCheckBox.leadingAnchor),
            checkBox.topAnchor.constraint(equalTo: inheritGlobalSettingCheckBox.bottomAnchor, constant: 5),
            checkBox.widthAnchor.constraint(equalTo: inheritGlobalSettingCheckBox.widthAnchor),
        ])
    }

    // 同步界面与设置
    func syncViewWithOptions() {
        // 继承
        inheritGlobalSettingCheckBox.state = NSControl.StateValue(rawValue: (currentTargetApplication?.inherit ?? false) ? 1 : 0)
        ignoreScrollSourceCheckBox?.state = (currentTargetApplication?.ignoreAsScrollSource ?? false) ? .on : .off
    }
}
