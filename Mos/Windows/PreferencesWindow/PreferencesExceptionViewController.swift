//
//  PreferencesExceptionViewController.swift
//  Mos
//  例外应用界面
//  Created by Caldis on 2017/1/29.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesExceptionViewController: NSViewController {
    
    // UI Elements
    // 白名单
    @IBOutlet weak var allowlistModeCheckBox: NSButton!
    // 表格及工具栏
    @IBOutlet weak var tableView: NSTableView!
    // 提示层
    @IBOutlet weak var noDataHint: NSView!
    // 选项菜单
    @IBOutlet var applicationSourceMenuControl: NSMenu!
    @IBOutlet weak var runningAndInstalledManuItem: NSMenuItem!
    @IBOutlet weak var runningAndInstalledMenuChildrenContainer: NSMenu!
    @IBOutlet weak var manuallySelectFromFinderMenuItem: NSMenuItem!
    @IBOutlet weak var manuallyInputMenuItem: NSMenuItem!
    
    override func viewDidLoad() {
        // 设置图标
        Utils.attachImage(to: runningAndInstalledManuItem, withImage: #imageLiteral(resourceName: "SF.wand.and.rays.inverse"))
        Utils.attachImage(to: manuallySelectFromFinderMenuItem, withImage: #imageLiteral(resourceName: "SF.tray"))
        Utils.attachImage(to: manuallyInputMenuItem, withImage: #imageLiteral(resourceName: "SF.pencil.and.ellipsis.rectangle"))
        // 读取设置
        syncViewWithOptions()
    }
    override func viewWillAppear() {
        // 检查表格数据
        toggleNoDataHint(animate: false)
    }
    
    // 白名单模式
    @IBAction func allowListModeClick(_ sender: NSButton) {
        Options.shared.general.allowlist = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 列表底部按钮
    @IBAction func addItemClick(_ sender: NSButton) {
        // 初始化运行中及已安装应用子菜单
        initRunningAndInstalledManuItem()
        // 显示菜单
        let targetPosition = NSPoint(x: sender.frame.origin.x, y: sender.frame.origin.y + sender.frame.height - 28)
        applicationSourceMenuControl.popUp(positioning: nil, at: targetPosition, in: sender.superview)
    }
    @IBAction func addItemFromFinderClick(_ sender: NSMenuItem) {
        // 添加
        openFileSelectPanel()
        // 重新加载
        tableView.reloadData()
    }
    @IBAction func addItemFromManullyInputClick(_ sender: NSMenuItem) {
        let exceptionInputViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.exceptionInput) as NSViewController
        presentAsSheet(exceptionInputViewController)
    }
    @IBAction func removeItemClick(_ sender: NSButton) {
        // 删除
        deleteTableViewSelectedRow()
        // 重新加载
        tableView.reloadData()
    }
}

/**
 * 设置同步
 **/
extension PreferencesExceptionViewController {
    // 同步界面与设置参数
    func syncViewWithOptions() {
        // 白名单
        allowlistModeCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.allowlist ? 1 : 0)
    }
}

/**
 * 表格区域渲染及操作
 **/
extension PreferencesExceptionViewController: NSTableViewDelegate, NSTableViewDataSource {
    // 每一列在 Storybroad 中的 identifier
    fileprivate enum CellIdentifiers {
        static let smoothCell = "smoothCell"
        static let reverseCell = "reverseCell"
        static let applicationCell = "applicationCell"
        static let settingCell = "settingCell"
    }
    // 切换无数据显示
    func toggleNoDataHint(animate: Bool = true) {
        let hasData = Options.shared.general.applications.count != 0
        if animate {
            noDataHint.animator().alphaValue = hasData ? 0 : 1
        } else {
            noDataHint.isHidden = hasData
        }
    }
    // 点击平滑
    @objc func smoothCheckBoxClick(_ sender: NSButton!) {
        let row = sender.tag
        let state = sender.state
        Options.shared.general.applications.get(from: row).scrollBasic.smooth = state.rawValue==1 ? true : false
    }
    // 点击反转
    @objc func reverseCheckBoxClick(_ sender: NSButton!) {
        let row = sender.tag
        let state = sender.state
        Options.shared.general.applications.get(from: row).scrollBasic.reverse = state.rawValue==1 ? true : false
    }
    // 点击设置
    @objc func settingButtonClick(_ sender: NSButton!) {
        let row = sender.tag
        let advancedWithApplicationViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.advancedWithApplication) as PreferencesAdvanceWithApplicationViewController
        advancedWithApplicationViewController.currentTargetApplication = Options.shared.general.applications.get(from: row)
        present(advancedWithApplicationViewController, asPopoverRelativeTo: sender.bounds, of: sender, preferredEdge: NSRectEdge.maxX, behavior: NSPopover.Behavior.transient)
    }
    // 构建表格数据 (循环生成行)
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // 如果对应列没有设置 Identifier 直接返回空
        guard let tableColumnIdentifier = tableColumn?.identifier else {
            return nil
        }
        // 生成每行的 Cell
        if let cell = tableView.makeView(withIdentifier: tableColumnIdentifier, owner: self) as? NSTableCellView {
            // 应用数据
            let application = Options.shared.general.applications.get(from: row)
            switch tableColumnIdentifier.rawValue {
                // 平滑
                case CellIdentifiers.smoothCell:
                    let checkBox = cell.nextKeyView as! NSButton
                    checkBox.tag = row
                    checkBox.target = self
                    checkBox.action = #selector(smoothCheckBoxClick)
                    checkBox.state = NSControl.StateValue(rawValue: application.scrollBasic.smooth==true ? 1 : 0)
                    return cell
                // 反转
                case CellIdentifiers.reverseCell:
                    let checkBox = cell.nextKeyView as! NSButton
                    checkBox.tag = row
                    checkBox.target = self
                    checkBox.action = #selector(reverseCheckBoxClick)
                    checkBox.state = NSControl.StateValue(rawValue: application.scrollBasic.reverse==true ? 1 : 0)
                    return cell
                // 应用
                case CellIdentifiers.applicationCell:
                    cell.imageView?.image = application.getIcon()
                    cell.textField?.stringValue = application.getName()
                    return cell
                // 设定
                case CellIdentifiers.settingCell:
                    let button = cell.subviews[0] as! NSButton
                    button.tag = row
                    button.target = self
                    button.action = #selector(settingButtonClick)
                    return cell
                default: break
            }
        }
        return nil
    }
    // 行高
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 30
    }
    // 行数
    func numberOfRows(in tableView: NSTableView) -> Int {
        let rows = Options.shared.general.applications.count
        toggleNoDataHint()
        return rows
    }
}



/**
 * 应用添加/删除控制
 */
extension PreferencesExceptionViewController: NSMenuDelegate {

    // 打开文件选择窗口
    func openFileSelectPanel() {
        let openPanel = NSOpenPanel()
        // 默认打开的目录 (/Application)
        openPanel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first!
        // 禁止选择文件夹
        openPanel.canChooseDirectories = false
        // 允许选择文件
        openPanel.canChooseFiles = true
        // 不允许复数选择
        openPanel.allowsMultipleSelection = false
        // 允许的文件类型
        openPanel.allowedFileTypes = ["app", "App", "APP"]
        // 打开文件选择窗口并读取文件添加到 ExceptionalApplications 列表中
        openPanel.beginSheetModal(for: view.window!, completionHandler: {
            result in
            if result.rawValue == NSFileHandlingPanelOKButton && result == NSApplication.ModalResponse.OK {
                // 根据路径获取 application 信息并保存到 ExceptionalApplications 列表中
                if let applicationPath = openPanel.url?.path, let applicationBundleId = Bundle(url: openPanel.url!)?.bundleIdentifier {
                    self.appendApplicationWith(path: applicationPath, bundleId: applicationBundleId)
                } else {
                    // 对于没有 bundleId 的应用可能是快捷方式, 给予提示
                }
            }
        })
    }

    // 初始化菜单
    func initRunningAndInstalledManuItem() {
        // 清除已有
        runningAndInstalledMenuChildrenContainer.removeAllItems()
        // 初始化 Running 应用
        let runningApplications = NSWorkspace.shared.runningApplications
        for application in runningApplications {
            guard application.activationPolicy == .regular else { continue }
            guard let bundleURL = application.bundleURL else { continue }
            let icon = Utils.getApplicationIcon(from: bundleURL)
            let name = Utils.getAppliactionName(from: bundleURL)
            let isExist = ScrollUtils.shared.applicationInExceptionalApplications(bundleId: application.bundleIdentifier) !== nil
            Utils.addMenuItem(
                to: runningAndInstalledMenuChildrenContainer,
                title: name, icon: icon,
                action: #selector(appendApplicationForSenderWithBundleURL),
                target: isExist ? nil : self,
                represent: bundleURL
            )
        }
        // 初始化 Installed 应用
//        let fileManager = FileManager.default
//        let applicationDirectoryURL = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first!
//        do {
//            let bundleURLs = try fileManager.contentsOfDirectory(at: applicationDirectoryURL, includingPropertiesForKeys: nil)
//            for bundleURL in bundleURLs {
//                let icon = Utils.getApplicationIcon(from: bundleURL)
//                let name = Utils.getAppliactionName(from: bundleURL)
//                Utils.addMenuItem(
//                    to: runningAndInstalledMenuChildrenContainer,
//                    title: name, icon: icon,
//                    action: #selector(appendApplicationForSenderWithBundleURL),
//                    target: self, represent: bundleURL
//                )
//            }
//        } catch {
//            print("Error while enumerating files \(applicationDirectoryURL.path): \(error.localizedDescription)")
//        }
    }
    
    // 添加应用
    func appendApplicationWith(path: String, bundleId: String) {
        let application = ExceptionalApplication(path: path, bundleId: bundleId)
        Options.shared.general.applications.append(application)
        self.tableView.reloadData()
    }
    func appendApplicationWith(name: String, bundleId: String) {
        let application = ExceptionalApplication(name: name, bundleId: bundleId)
        Options.shared.general.applications.append(application)
        self.tableView.reloadData()
    }
    @objc func appendApplicationForSenderWithBundleURL(_ sender: NSMenuItem!) {
        let url = sender.representedObject as! URL
        let path = url.path
        let bundleId = Bundle(url: url)!.bundleIdentifier!
        appendApplicationWith(path: path, bundleId: bundleId)
    }
    
    // 删除选定行
    func deleteTableViewSelectedRow() {
        // 确保有选中特定行
        if tableView.selectedRow != -1 {
            Options.shared.general.applications.remove(at: tableView.selectedRow)
        }
    }
}
