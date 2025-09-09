//
//  PreferencesApplicationViewController.swift
//  Mos
//  分应用设置界面
//  Created by Caldis on 2017/1/29.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesApplicationViewController: NSViewController {
    
    // MARK: - UI Elements
    // 白名单
    @IBOutlet weak var allowlistModeCheckBox: NSButton!
    // 表格
    @IBOutlet weak var tableHead: NSVisualEffectView!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableFoot: NSView!
    @IBOutlet weak var tableEmpty: NSView!
    // 添加按钮
    @IBOutlet weak var addButton: AddButton!
    // 选项菜单
    @IBOutlet var applicationSourceMenuControl: NSMenu!
    @IBOutlet weak var runningAndInstalledManuItem: NSMenuItem!
    @IBOutlet weak var runningAndInstalledMenuChildrenContainer: NSMenu!
    @IBOutlet weak var manuallySelectFromFinderMenuItem: NSMenuItem!
    
    override func viewDidLoad() {
        // 设置图标
        Utils.attachImage(to: runningAndInstalledManuItem, withImage: #imageLiteral(resourceName: "SF.wand.and.rays.inverse"))
        Utils.attachImage(to: manuallySelectFromFinderMenuItem, withImage: #imageLiteral(resourceName: "SF.tray"))
        // 读取设置
        syncViewWithOptions()
    }
    override func viewWillAppear() {
        // 检查表格数据
        toggleNoDataHint(animate: false)
        // 设置添加按钮回调
        setupAddButtonCallback()
    }
    
    // 主添加按钮
    private func setupAddButtonCallback() {
        addButton.onMouseDown = { [weak self] _ in
            guard let self = self else { return }
            guard let sender = self.addButton else { return }
            let position = NSPoint(x: sender.frame.origin.x - 40, y: sender.frame.origin.y + sender.frame.height - 91)
            self.openRunningApplicationPanel(sender, position)
            self.tableView.reloadData()
        }
    }
    
    // 白名单模式
    @IBAction func allowListModeClick(_ sender: NSButton) {
        Options.shared.application.allowlist = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 列表底部按钮
    @IBAction func addItemClick(_ sender: NSButton) {
        // 添加
        let position = NSPoint(x: sender.frame.origin.x - 3, y: sender.frame.origin.y + sender.frame.height)
        openRunningApplicationPanel(sender, position)
        // 重新加载
        tableView.reloadData()
    }
    @IBAction func addItemFromFinderClick(_ sender: NSMenuItem) {
        // 添加
        openFileSelectionPanel()
        // 重新加载
        tableView.reloadData()
    }
    @IBAction func removeItemClick(_ sender: NSButton) {
        // 删除
        deleteTableViewSelectedRow()
        // 重新加载
        tableView.reloadData()
        // 立即更新空状态显示
        toggleNoDataHint()
    }
}

/**
 * 设置同步
 **/
extension PreferencesApplicationViewController {
    // 同步界面与设置参数
    func syncViewWithOptions() {
        // 白名单
        allowlistModeCheckBox.state = NSControl.StateValue(rawValue: Options.shared.application.allowlist ? 1 : 0)
    }
}

/**
 * 表格区域渲染及操作
 **/
extension PreferencesApplicationViewController: NSTableViewDelegate, NSTableViewDataSource {
    // 每一列在 Storybroad 中的 identifier
    fileprivate enum CellIdentifiers {
        static let applicationCell = "applicationCell"
        static let settingCell = "settingCell"
    }
    // 切换无数据显示
    func toggleNoDataHint(animate: Bool = true) {
        let hasData = Options.shared.application.applications.count != 0
        if animate {
            tableEmpty.isHidden = hasData
            tableEmpty.animator().alphaValue = hasData ? 0 : 1
            addButton.isHidden = hasData
            addButton.animator().alphaValue = hasData ? 0 : 1
            tableHead.isHidden = !hasData
            tableHead.animator().alphaValue = hasData ? 1 : 0
            tableFoot.isHidden = !hasData
            tableFoot.animator().alphaValue = hasData ? 1 : 0
        } else {
            tableEmpty.isHidden = hasData
            tableEmpty.alphaValue = hasData ? 0 : 1
            addButton.isHidden = hasData
            addButton.alphaValue = hasData ? 0 : 1
            tableHead.isHidden = !hasData
            tableHead.alphaValue = hasData ? 1 : 0
            tableFoot.isHidden = !hasData
            tableFoot.alphaValue = hasData ? 1 : 0
        }
    }
    // 点击设置
    @objc func settingButtonClick(_ sender: NSButton!) {
        let row = sender.tag
        let scrollingWithApplicationViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.scrollingWithApplication) as PreferencesScrollingWithApplicationViewController
        scrollingWithApplicationViewController.updateTargetApplication(with: Options.shared.application.applications.get(by: row))
        scrollingWithApplicationViewController.updateParentData(with: tableView, for: row)
        present(scrollingWithApplicationViewController, asPopoverRelativeTo: sender.bounds, of: sender, preferredEdge: NSRectEdge.maxX, behavior: NSPopover.Behavior.transient)
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
            let application = Options.shared.application.applications.get(by: row)
            switch tableColumnIdentifier.rawValue {
                // 应用
                case CellIdentifiers.applicationCell:
                    cell.imageView?.image = application?.getIcon()
                    cell.imageView?.toolTip = application?.path
                    cell.textField?.stringValue = application?.getName() ?? ""
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
        return Options.shared.application.applications.count
    }
}



/**
 * 应用添加/删除控制
 */
extension PreferencesApplicationViewController: NSMenuDelegate {

    // 打开文件选择窗口
    func openFileSelectionPanel() {
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
        // openPanel.allowedFileTypes = ["app", "App", "APP"]
        // 打开文件选择窗口并读取文件添加到 Applications 列表中
        openPanel.beginSheetModal(for: view.window!, completionHandler: { result in
            if result.rawValue == NSApplication.ModalResponse.OK.rawValue && result == NSApplication.ModalResponse.OK {
                // 根据路径获取 application 信息并保存到 Applications 列表中
                if let bundlePath = openPanel.url?.path {
                    self.appendApplicationWith(path: bundlePath)
                }
            }
        })
    }

    // 初始化菜单
    func openRunningApplicationPanel(_ targetView: NSView, _ targetPosition: NSPoint) {
        // 清除已有
        runningAndInstalledMenuChildrenContainer.removeAllItems()
        // 初始化 Running 应用
        for runningApplication in NSWorkspace.shared.runningApplications {
            guard runningApplication.activationPolicy == .regular else { continue }
            let icon = Utils.getApplicationIcon(fromPath: runningApplication.bundleURL?.path)
            let name = Utils.getApplicationName(fromPath: runningApplication.executableURL?.path)
            let isExist = ScrollUtils.shared.getTargetApplication(from: runningApplication) !== nil
            Utils.addMenuItem(
                to: runningAndInstalledMenuChildrenContainer,
                title: name,
                icon: icon,
                action: #selector(appendApplicationWithRunningApplication),
                target: isExist ? nil : self,
                represent: runningApplication
            )
        }
        // 显示菜单
        applicationSourceMenuControl.popUp(positioning: nil, at: targetPosition, in: targetView)
    }
    
    // 添加应用
    func appendApplicationWith(path: String) {
        let application = Application(path: path)
        Options.shared.application.applications.append(application)
        tableView.reloadData()
        toggleNoDataHint()
    }
    @objc func appendApplicationWithRunningApplication(_ sender: NSMenuItem!) {
        guard let runningApplication = sender.representedObject as? NSRunningApplication else { return }
        guard let executablePath = runningApplication.executableURL?.path else { return }
        appendApplicationWith(path: executablePath)
    }
    
    // 删除选定行
    func deleteTableViewSelectedRow() {
        // 确保有选中特定行
        if tableView.selectedRow != -1 {
            Options.shared.application.applications.remove(at: tableView.selectedRow)
        }
    }
}
