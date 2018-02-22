//
//  PreferencesExceptionViewController.swift
//  Mos
//  例外应用界面
//  Created by Caldis on 2017/1/29.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesExceptionViewController: NSViewController {
    
    // 白名单CheckBox
    @IBOutlet weak var whiteListModeCheckBox: NSButton!
    // 表格, 表格底部工具栏
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableViewToolBar: NSSegmentedControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 恢复一下设置
        whiteListModeCheckBox.state = NSControl.StateValue(rawValue: Options.shared.current.exception.whitelist ? 1 : 0)
    }
    
    // 是否启用白名单模式
    @IBAction func whiteListModeClick(_ sender: NSButton) {
        if sender.state.rawValue == 0 {
            Options.shared.current.exception.whitelist = false
        } else {
            Options.shared.current.exception.whitelist = true
        }
        // 保存设置
        UserDefaults.standard.set(Options.shared.current.exception.whitelist ? "true" : "false", forKey:"whiteListMode")
    }
    
    // 列表底部的工具栏
    @IBAction func tableViewToolBarClick(_ sender: NSSegmentedControl) {
        // 添加按钮
        if sender.selectedSegment == 0 {
            openFileSelectPanel()
        }
        // 删除按钮
        if sender.selectedSegment == 1 {
            deleteTableViewSelectedRow()
        }
        // 重新load一次数据
        tableView.reloadData()
    }
    
    // 打开文件选择窗口
    func openFileSelectPanel() {
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = NSURL.fileURL(withPath: "/application", isDirectory: true)
        // 禁止选择文件夹
        openPanel.canChooseDirectories = false
        // 能选择文件
        openPanel.canChooseFiles = true
        // 不允许复数选择
        openPanel.allowsMultipleSelection = false
        // 允许的文件类型
        openPanel.allowedFileTypes = ["app", "App", "APP"]
        // 打开文件选择窗口并读取文件添加到 ExceptionalApplications 列表中
        openPanel.beginSheetModal(for: PreferencesWindowController.preferenceWindowRef, completionHandler: {
            result in
                if result.rawValue == NSFileHandlingPanelOKButton && result == NSApplication.ModalResponse.OK {
                    // 根据路径获取 application 信息并保存到 ExceptionalApplications 列表中
                    let applicationUrl = String(describing: openPanel.url!)
                    let applicationPath = openPanel.url!.path
                    let applicationIcon = NSWorkspace.shared.icon(forFile: applicationPath)
                    let applicationName = FileManager().displayName(atPath: applicationUrl).removingPercentEncoding!
                    if let applicationBundleId = Bundle(url: openPanel.url!)?.bundleIdentifier {
                        let application = ExceptionalApplication(smooth: true, reverse: true, title: applicationName, bundleId: applicationBundleId)
                        Options.shared.current.exception.applicationsDict[applicationBundleId] = application
                        self.tableView.reloadData()
                    } else {
                        // Todo: 对于没有bundleId的应用可能是快捷方式, 给个提示
                        print("Just a shortcut")
                    }
                }
        })
    }
    
    // 删除 TableView 选定的行
    func deleteTableViewSelectedRow() {
        // 防止点击过快
        if tableView.selectedRow != -1 {
            Options.shared.current.exception.applications.remove(at: tableView.selectedRow)
        }
    }
    
    // smooth 列的 checkbox 被点击, 设置对应行的信息
    @objc func smoothClick(_ sender: NSButton!) {
        let row = sender.tag
        let state = sender.state
        Options.shared.current.exception.applications[row].smooth = state.rawValue==1 ? true : false
    }
    // reverse 列的 checkbox 被点击, 设置对应行的信息
    @objc func reverseClick(_ sender: NSButton!) {
        let row = sender.tag
        let state = sender.state
        Options.shared.current.exception.applications[row].reverse = state.rawValue==1 ? true : false
    }
    
}



extension PreferencesExceptionViewController: NSTableViewDataSource {
    
    // 行数
    func numberOfRows(in tableView: NSTableView) -> Int {
        return Options.shared.current.exception.applications.count
    }
    
}



extension PreferencesExceptionViewController: NSTableViewDelegate {
    
    // 每一列在Storybroad中的名字
    fileprivate enum CellIdentifiers {
        static let smoothCell = "smoothCell"
        static let reverseCell = "reverseCell"
        static let applicationCell = "applicationCell"
    }
    
    // 构建table数据
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        // 如果对应列没有设置identifier直接返回空
        guard let tableColumnIdentifier = tableColumn?.identifier else {
            return nil
        }
        
        // 生成每个Cell
        if let cell = tableView.makeView(withIdentifier: tableColumnIdentifier, owner: self) as? NSTableCellView {
            let rowItem = Options.shared.current.exception.applications[row]
            // smooth 列
            if tableColumnIdentifier.rawValue == CellIdentifiers.smoothCell {
                let checkBox = cell.nextKeyView as! NSButton
                checkBox.tag = row
                checkBox.target = self
                checkBox.action = #selector(smoothClick(_:))
                checkBox.state = NSControl.StateValue(rawValue: rowItem.smooth==true ? 1 : 0)
                return cell
            }
            // reverse 列
            if tableColumnIdentifier.rawValue == CellIdentifiers.reverseCell {
                let checkBox = cell.nextKeyView as! NSButton
                checkBox.tag = row
                checkBox.target = self
                checkBox.action = #selector(reverseClick(_:))
                checkBox.state = NSControl.StateValue(rawValue: rowItem.reverse==true ? 1 : 0)
                return cell
            }
            // application 列
            if tableColumnIdentifier.rawValue == CellIdentifiers.applicationCell {
//                cell.imageView?.image = rowItem.icon ?? nil
                cell.textField?.stringValue = rowItem.title
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
