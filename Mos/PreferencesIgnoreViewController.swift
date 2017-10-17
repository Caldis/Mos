//
//  PreferencesIgnoreViewController.swift
//  Mos
//
//  Created by Cb on 2017/1/29.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class PreferencesIgnoreViewController: NSViewController {
    
    // 白名单CheckBox
    @IBOutlet weak var whiteListModeCheckBox: NSButton!
    // 表格, 表格底部工具栏
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableViewToolBar: NSSegmentedControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 恢复一下设置
        whiteListModeCheckBox.state = NSControl.StateValue(rawValue: ScrollCore.whiteListMode ? 1 : 0)
    }
    
    // 是否启用白名单模式
    @IBAction func whiteListModeClick(_ sender: NSButton) {
        if sender.state.rawValue == 0 {
            ScrollCore.whiteListMode = false
        } else {
            ScrollCore.whiteListMode = true
        }
        // 保存设置
        UserDefaults.standard.set(ScrollCore.whiteListMode ? "true" : "false", forKey:"whiteListMode")
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
        // 打开文件选择窗口并读取文件添加到 ignoredApplications
        openPanel.beginSheetModal(for: PreferencesWindowController.preferenceWindowRef, completionHandler: {
            result in
                if result.rawValue == NSFileHandlingPanelOKButton && result == NSApplication.ModalResponse.OK {
                    // 根据路径获取application信息并保存到ignoredApplications列表中
                    let applicationUrl = String(describing: openPanel.url!)
                    let applicationPath = openPanel.url!.path
                    let applicationIcon = NSWorkspace.shared.icon(forFile: applicationPath)
                    let applicationName = FileManager().displayName(atPath: applicationUrl).removingPercentEncoding!
                    if let applicationBundleId = Bundle(url: openPanel.url!)?.bundleIdentifier {
                        // 添加的例外应用的默认状态与是否启用白名单模式挂钩, 如果启用了白名单模式, 则默认都不禁用; 如果未启用白名单模式, 则默认都禁用
                        let application = IgnoredApplication(notSmooth: !ScrollCore.whiteListMode, notReverse: !ScrollCore.whiteListMode, icon: applicationIcon, title: applicationName, bundleId: applicationBundleId)
                        ScrollCore.ignoredApplications.append(application)
                        ScrollCore.updateIgnoreList()
                        self.tableView.reloadData()
                    } else {
                        // Todo: 对于没有bundleId的应用可能是快捷方式, 给个提示
                        print("Just a shortcut")
                    }
                }
        })
    }
    
    // 删除TableView选定的行
    func deleteTableViewSelectedRow() {
        // 防止点击过快
        if tableView.selectedRow != -1 {
            ScrollCore.ignoredApplications.remove(at: tableView.selectedRow)
            ScrollCore.updateIgnoreList()
        }
    }
    
    // notSmooth列的checkbox被点击, 设置对应行的信息
    @objc func notSmoothClick(_ sender: NSButton!) {
        let row = sender.tag
        let state = sender.state
        ScrollCore.ignoredApplications[row].notSmooth = state.rawValue==1 ? true : false
        ScrollCore.updateIgnoreList()
    }
    // notReverse列的checkbox被点击, 设置对应行的信息
    @objc func notReverseClick(_ sender: NSButton!) {
        let row = sender.tag
        let state = sender.state
        ScrollCore.ignoredApplications[row].notReverse = state.rawValue==1 ? true : false
        ScrollCore.updateIgnoreList()
    }
    
}



extension PreferencesIgnoreViewController: NSTableViewDataSource {
    
    // 行数
    func numberOfRows(in tableView: NSTableView) -> Int {
        return ScrollCore.ignoredApplications.count
    }
    
}



extension PreferencesIgnoreViewController: NSTableViewDelegate {
    
    // 每一列在Storybroad中的名字
    fileprivate enum CellIdentifiers {
        static let notSmoothCell = "notSmoothCell"
        static let notReverseCell = "notReverseCell"
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
            let rowItem = ScrollCore.ignoredApplications[row]
            // notSmooth列, 绑定对应方法
            if tableColumnIdentifier.rawValue == CellIdentifiers.notSmoothCell {
                let checkBox = cell.nextKeyView as! NSButton
                checkBox.tag = row
                checkBox.target = self
                checkBox.action = #selector(notSmoothClick(_:))
                checkBox.state = NSControl.StateValue(rawValue: rowItem.notSmooth==true ? 1 : 0)
                return cell
            }
            // notReverse列, 绑定对应方法
            if tableColumnIdentifier.rawValue == CellIdentifiers.notReverseCell {
                let checkBox = cell.nextKeyView as! NSButton
                checkBox.tag = row
                checkBox.target = self
                checkBox.action = #selector(notReverseClick(_:))
                checkBox.state = NSControl.StateValue(rawValue: rowItem.notReverse==true ? 1 : 0)
                return cell
            }
            // application列
            if tableColumnIdentifier.rawValue == CellIdentifiers.applicationCell {
                cell.imageView?.image = rowItem.icon ?? nil
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
