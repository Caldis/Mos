//
//  PreferencesExceptionViewController.swift
//  Mos
//  例外应用界面
//  Created by Caldis on 2017/1/29.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesExceptionViewController: NSViewController {
    
    // 白名单
    @IBOutlet weak var whitelistModeCheckBox: NSButton!
    // 表格及工具栏
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableViewToolBar: NSSegmentedControl!
    // 提示层
    @IBOutlet weak var noDataHint: NSView!
    // 检查授权定时器
    var checkAccessibilityTimer: Timer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 读取设置
        syncViewWithOptions()
    }
    override func viewWillAppear() {
        // 检查表格数据
        checkListHasData(animate: false)
    }
    
    // 检查表格数据
    func checkListHasData(animate: Bool = true) {
        let hasData = Options.shared.exception.applications.count != 0
        if animate {
            noDataHint.animator().alphaValue = hasData ? 0 : 1
        } else {
            noDataHint.isHidden = hasData
        }
    }
    
    // 白名单模式
    @IBAction func whiteListModeClick(_ sender: NSButton) {
        Options.shared.exception.whitelist = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 列表底部工具栏
    @IBAction func tableViewToolBarClick(_ sender: NSSegmentedControl) {
        // 添加
        if sender.selectedSegment == 0 {
            openFileSelectPanel()
        }
        // 删除
        if sender.selectedSegment == 1 {
            deleteTableViewSelectedRow()
        }
        // 重新加载
        tableView.reloadData()
    }
    
    // 打开文件选择窗口
    func openFileSelectPanel() {
        // 当前的容器窗口引用
        let currentWindowController = WindowManager.shared.refs[WindowManager.shared.identifier.preferencesWindowController]!.window!
        let openPanel = NSOpenPanel()
        // 默认打开的目录 (/application)
        openPanel.directoryURL = NSURL.fileURL(withPath: "/application", isDirectory: true)
        // 禁止选择文件夹
        openPanel.canChooseDirectories = false
        // 允许选择文件
        openPanel.canChooseFiles = true
        // 不允许复数选择
        openPanel.allowsMultipleSelection = false
        // 允许的文件类型
        openPanel.allowedFileTypes = ["app", "App", "APP"]
        // 打开文件选择窗口并读取文件添加到 ExceptionalApplications 列表中
        openPanel.beginSheetModal(for: currentWindowController, completionHandler: {
            result in
                if result.rawValue == NSFileHandlingPanelOKButton && result == NSApplication.ModalResponse.OK {
                    // 根据路径获取 application 信息并保存到 ExceptionalApplications 列表中
                    let applicationPath = openPanel.url!.path
                    let applicationName = FileManager().displayName(atPath: String(describing: openPanel.url!)).removingPercentEncoding!
                    if let applicationBundleId = Bundle(url: openPanel.url!)?.bundleIdentifier {
                        let application = ExceptionalApplication(path: applicationPath, title: applicationName, bundleId: applicationBundleId)
                        Options.shared.exception.applications.append(application)
                        self.tableView.reloadData()
                    } else {
                        // 对于没有 bundleId 的应用可能是快捷方式, 给予提示
                    }
                }
        })
    }
    // 删除选定行
    func deleteTableViewSelectedRow() {
        // 确保有选中特定行
        if tableView.selectedRow != -1 {
            Options.shared.exception.applications.remove(at: tableView.selectedRow)
        }
    }
    
    // 点击平滑
    @objc func smoothCheckBoxClick(_ sender: NSButton!) {
        let row = sender.tag
        let state = sender.state
        Options.shared.exception.applications[row].smooth = state.rawValue==1 ? true : false
    }
    // 点击反转
    @objc func reverseCheckBoxClick(_ sender: NSButton!) {
        let row = sender.tag
        let state = sender.state
        Options.shared.exception.applications[row].reverse = state.rawValue==1 ? true : false
    }
    
    // 同步界面与设置参数
    func syncViewWithOptions() {
        // 白名单
        whitelistModeCheckBox.state = NSControl.StateValue(rawValue: Options.shared.exception.whitelist ? 1 : 0)
    }
    
}

/**
 * 表格行内容
 **/
extension PreferencesExceptionViewController: NSTableViewDelegate {
    // 每一列在 Storybroad 中的 identifier
    fileprivate enum CellIdentifiers {
        static let smoothCell = "smoothCell"
        static let reverseCell = "reverseCell"
        static let applicationCell = "applicationCell"
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
            let application = Options.shared.exception.applications[row]
            let applicationIcon = NSWorkspace.shared.icon(forFile: application.path)
            // 平滑
            if tableColumnIdentifier.rawValue == CellIdentifiers.smoothCell {
                let checkBox = cell.nextKeyView as! NSButton
                checkBox.tag = row
                checkBox.target = self
                checkBox.action = #selector(smoothCheckBoxClick)
                checkBox.state = NSControl.StateValue(rawValue: application.smooth==true ? 1 : 0)
                return cell
            }
            // 反转
            if tableColumnIdentifier.rawValue == CellIdentifiers.reverseCell {
                let checkBox = cell.nextKeyView as! NSButton
                checkBox.tag = row
                checkBox.target = self
                checkBox.action = #selector(reverseCheckBoxClick)
                checkBox.state = NSControl.StateValue(rawValue: application.reverse==true ? 1 : 0)
                return cell
            }
            // 应用
            if tableColumnIdentifier.rawValue == CellIdentifiers.applicationCell {
                cell.imageView?.image = applicationIcon
                cell.textField?.stringValue = application.title
                return cell
            }
        }
        return nil
    }
    // 行高
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 30
    }
}

/**
 * 表格数据源
 **/
extension PreferencesExceptionViewController: NSTableViewDataSource {
    // 行数
    func numberOfRows(in tableView: NSTableView) -> Int {
        let rows = Options.shared.exception.applications.count
        checkListHasData()
        return rows
    }
}
