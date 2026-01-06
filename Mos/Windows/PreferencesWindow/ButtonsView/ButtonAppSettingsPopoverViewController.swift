//
//  ButtonAppSettingsPopoverViewController.swift
//  Mos
//  按钮绑定的分应用设置弹出窗口
//  Created by Claude on 2025/1/6.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class ButtonAppSettingsPopoverViewController: NSViewController {
    
    // MARK: - Callbacks
    private var onDisabledAppsChanged: (([ButtonApplicationRule]) -> Void)?
    private var onEnabledAppsChanged: (([ButtonApplicationRule]) -> Void)?
    private var onDefaultModeChanged: ((Bool) -> Void)?
    
    // MARK: - Data
    private var currentBinding: ButtonBinding?
    private var disabledApplications: [ButtonApplicationRule] = []
    private var enabledApplications: [ButtonApplicationRule] = []
    
    // MARK: - UI Elements
    private var titleLabel: NSTextField!
    
    // 禁用列表区域
    private var disabledSectionLabel: NSTextField!
    private var disabledTableView: NSTableView!
    private var disabledScrollView: NSScrollView!
    private var disabledAddButton: NSButton!
    private var disabledRemoveButton: NSButton!
    private var disabledEmptyLabel: NSTextField!
    
    // 启用列表区域
    private var enabledSectionLabel: NSTextField!
    private var enabledTableView: NSTableView!
    private var enabledScrollView: NSScrollView!
    private var enabledAddButton: NSButton!
    private var enabledRemoveButton: NSButton!
    private var enabledEmptyLabel: NSTextField!
    
    // MARK: - Menu
    private var applicationMenu: NSMenu!
    private var currentAddTarget: String = "" // "disabled" or "enabled"
    
    // MARK: - Lifecycle
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 480))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateUI()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        // 每次显示时刷新 UI，确保显示最新数据
        updateUI()
    }
    
    // MARK: - Configuration
    
    func configure(
        with binding: ButtonBinding,
        onDisabledAppsChanged: @escaping ([ButtonApplicationRule]) -> Void,
        onEnabledAppsChanged: @escaping ([ButtonApplicationRule]) -> Void,
        onDefaultModeChanged: @escaping (Bool) -> Void
    ) {
        self.currentBinding = binding
        self.disabledApplications = binding.disabledApplications
        self.enabledApplications = binding.enabledApplications
        self.onDisabledAppsChanged = onDisabledAppsChanged
        self.onEnabledAppsChanged = onEnabledAppsChanged
        self.onDefaultModeChanged = onDefaultModeChanged
        
        // 如果视图已加载，立即更新 UI
        if isViewLoaded {
            updateUI()
        }
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        // 标题
        titleLabel = NSTextField(labelWithString: NSLocalizedString("button.app.settings.title", comment: ""))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // ===== 禁用列表区域 =====
        disabledSectionLabel = NSTextField(labelWithString: NSLocalizedString("button.app.settings.disabled.title", comment: ""))
        disabledSectionLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        disabledSectionLabel.textColor = NSColor.secondaryLabelColor
        disabledSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(disabledSectionLabel)
        
        setupDisabledTableView()
        
        disabledEmptyLabel = NSTextField(labelWithString: NSLocalizedString("button.app.settings.disabled.empty", comment: ""))
        disabledEmptyLabel.font = NSFont.systemFont(ofSize: 11)
        disabledEmptyLabel.textColor = NSColor.tertiaryLabelColor
        disabledEmptyLabel.alignment = .center
        disabledEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(disabledEmptyLabel)
        
        disabledAddButton = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(disabledAddButtonClicked(_:)))
        disabledAddButton.bezelStyle = .smallSquare
        disabledAddButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(disabledAddButton)
        
        disabledRemoveButton = NSButton(image: NSImage(named: NSImage.removeTemplateName)!, target: self, action: #selector(disabledRemoveButtonClicked(_:)))
        disabledRemoveButton.bezelStyle = .smallSquare
        disabledRemoveButton.translatesAutoresizingMaskIntoConstraints = false
        disabledRemoveButton.isEnabled = false
        view.addSubview(disabledRemoveButton)
        
        // ===== 启用列表区域 =====
        enabledSectionLabel = NSTextField(labelWithString: NSLocalizedString("button.app.settings.enabled.title", comment: ""))
        enabledSectionLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        enabledSectionLabel.textColor = NSColor.secondaryLabelColor
        enabledSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enabledSectionLabel)
        
        setupEnabledTableView()
        
        enabledEmptyLabel = NSTextField(labelWithString: NSLocalizedString("button.app.settings.enabled.empty", comment: ""))
        enabledEmptyLabel.font = NSFont.systemFont(ofSize: 11)
        enabledEmptyLabel.textColor = NSColor.tertiaryLabelColor
        enabledEmptyLabel.alignment = .center
        enabledEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enabledEmptyLabel)
        
        enabledAddButton = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(enabledAddButtonClicked(_:)))
        enabledAddButton.bezelStyle = .smallSquare
        enabledAddButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enabledAddButton)
        
        enabledRemoveButton = NSButton(image: NSImage(named: NSImage.removeTemplateName)!, target: self, action: #selector(enabledRemoveButtonClicked(_:)))
        enabledRemoveButton.bezelStyle = .smallSquare
        enabledRemoveButton.translatesAutoresizingMaskIntoConstraints = false
        enabledRemoveButton.isEnabled = false
        view.addSubview(enabledRemoveButton)
        
        // 布局
        NSLayoutConstraint.activate([
            // 标题
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // 禁用列表标题
            disabledSectionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            disabledSectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            // 禁用列表表格
            disabledScrollView.topAnchor.constraint(equalTo: disabledSectionLabel.bottomAnchor, constant: 6),
            disabledScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            disabledScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            disabledScrollView.heightAnchor.constraint(equalToConstant: 100),
            
            // 禁用列表空状态
            disabledEmptyLabel.centerXAnchor.constraint(equalTo: disabledScrollView.centerXAnchor),
            disabledEmptyLabel.centerYAnchor.constraint(equalTo: disabledScrollView.centerYAnchor),
            
            // 禁用列表按钮
            disabledAddButton.topAnchor.constraint(equalTo: disabledScrollView.bottomAnchor, constant: 4),
            disabledAddButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            disabledAddButton.widthAnchor.constraint(equalToConstant: 22),
            disabledAddButton.heightAnchor.constraint(equalToConstant: 22),
            
            disabledRemoveButton.topAnchor.constraint(equalTo: disabledScrollView.bottomAnchor, constant: 4),
            disabledRemoveButton.leadingAnchor.constraint(equalTo: disabledAddButton.trailingAnchor, constant: 2),
            disabledRemoveButton.widthAnchor.constraint(equalToConstant: 22),
            disabledRemoveButton.heightAnchor.constraint(equalToConstant: 22),
            
            // 启用列表标题
            enabledSectionLabel.topAnchor.constraint(equalTo: disabledAddButton.bottomAnchor, constant: 16),
            enabledSectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            // 启用列表表格
            enabledScrollView.topAnchor.constraint(equalTo: enabledSectionLabel.bottomAnchor, constant: 6),
            enabledScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            enabledScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            enabledScrollView.heightAnchor.constraint(equalToConstant: 100),
            
            // 启用列表空状态
            enabledEmptyLabel.centerXAnchor.constraint(equalTo: enabledScrollView.centerXAnchor),
            enabledEmptyLabel.centerYAnchor.constraint(equalTo: enabledScrollView.centerYAnchor),
            
            // 启用列表按钮
            enabledAddButton.topAnchor.constraint(equalTo: enabledScrollView.bottomAnchor, constant: 4),
            enabledAddButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            enabledAddButton.widthAnchor.constraint(equalToConstant: 22),
            enabledAddButton.heightAnchor.constraint(equalToConstant: 22),
            enabledAddButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            
            enabledRemoveButton.topAnchor.constraint(equalTo: enabledScrollView.bottomAnchor, constant: 4),
            enabledRemoveButton.leadingAnchor.constraint(equalTo: enabledAddButton.trailingAnchor, constant: 2),
            enabledRemoveButton.widthAnchor.constraint(equalToConstant: 22),
            enabledRemoveButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        
        // 设置应用选择菜单
        setupApplicationMenu()
    }
    
    private func setupDisabledTableView() {
        disabledScrollView = NSScrollView(frame: .zero)
        disabledScrollView.translatesAutoresizingMaskIntoConstraints = false
        disabledScrollView.hasVerticalScroller = true
        disabledScrollView.borderType = .bezelBorder
        
        disabledTableView = NSTableView(frame: .zero)
        disabledTableView.delegate = self
        disabledTableView.dataSource = self
        disabledTableView.headerView = nil
        disabledTableView.rowHeight = 24
        disabledTableView.tag = 1 // 用于区分表格
        disabledTableView.allowsEmptySelection = true
        disabledTableView.allowsMultipleSelection = false
        disabledTableView.selectionHighlightStyle = .regular
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("disabledColumn"))
        column.width = 260
        disabledTableView.addTableColumn(column)
        
        disabledScrollView.documentView = disabledTableView
        view.addSubview(disabledScrollView)
    }
    
    private func setupEnabledTableView() {
        enabledScrollView = NSScrollView(frame: .zero)
        enabledScrollView.translatesAutoresizingMaskIntoConstraints = false
        enabledScrollView.hasVerticalScroller = true
        enabledScrollView.borderType = .bezelBorder
        
        enabledTableView = NSTableView(frame: .zero)
        enabledTableView.delegate = self
        enabledTableView.dataSource = self
        enabledTableView.headerView = nil
        enabledTableView.rowHeight = 24
        enabledTableView.tag = 2 // 用于区分表格
        enabledTableView.allowsEmptySelection = true
        enabledTableView.allowsMultipleSelection = false
        enabledTableView.selectionHighlightStyle = .regular
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabledColumn"))
        column.width = 260
        enabledTableView.addTableColumn(column)
        
        enabledScrollView.documentView = enabledTableView
        view.addSubview(enabledScrollView)
    }
    
    private func setupApplicationMenu() {
        applicationMenu = NSMenu()
    }
    
    // MARK: - UI Update
    
    private func updateUI() {
        // 更新表格
        disabledTableView.reloadData()
        enabledTableView.reloadData()
        
        // 更新空状态
        disabledEmptyLabel.isHidden = !disabledApplications.isEmpty
        enabledEmptyLabel.isHidden = !enabledApplications.isEmpty
        
        // 更新删除按钮状态
        disabledRemoveButton.isEnabled = disabledTableView.selectedRow != -1
        enabledRemoveButton.isEnabled = enabledTableView.selectedRow != -1
    }
    
    // MARK: - Actions
    
    @objc private func disabledAddButtonClicked(_ sender: NSButton) {
        currentAddTarget = "disabled"
        showApplicationMenu(from: sender, excludingPaths: disabledApplications.map { $0.applicationPath })
    }
    
    @objc private func disabledRemoveButtonClicked(_ sender: NSButton) {
        let selectedRow = disabledTableView.selectedRow
        guard selectedRow >= 0 && selectedRow < disabledApplications.count else { return }
        
        disabledApplications.remove(at: selectedRow)
        onDisabledAppsChanged?(disabledApplications)
        updateUI()
    }
    
    @objc private func enabledAddButtonClicked(_ sender: NSButton) {
        currentAddTarget = "enabled"
        showApplicationMenu(from: sender, excludingPaths: enabledApplications.map { $0.applicationPath })
    }
    
    @objc private func enabledRemoveButtonClicked(_ sender: NSButton) {
        let selectedRow = enabledTableView.selectedRow
        guard selectedRow >= 0 && selectedRow < enabledApplications.count else { return }
        
        enabledApplications.remove(at: selectedRow)
        onEnabledAppsChanged?(enabledApplications)
        updateUI()
    }
    
    private func showApplicationMenu(from button: NSButton, excludingPaths: [String]) {
        applicationMenu.removeAllItems()
        
        for runningApp in NSWorkspace.shared.runningApplications {
            guard runningApp.activationPolicy == .regular else { continue }
            guard let executablePath = runningApp.executableURL?.path else { continue }
            
            // 检查是否已在任一列表中
            let isAlreadyAdded = excludingPaths.contains(executablePath)
            
            let icon = Utils.getApplicationIcon(fromPath: runningApp.bundleURL?.path)
            let name = runningApp.localizedName ?? Utils.getApplicationName(fromPath: executablePath)
            
            let menuItem = NSMenuItem(title: name, action: isAlreadyAdded ? nil : #selector(addApplicationFromMenu(_:)), keyEquivalent: "")
            menuItem.target = isAlreadyAdded ? nil : self
            menuItem.image = icon
            menuItem.image?.size = NSSize(width: 16, height: 16)
            menuItem.representedObject = runningApp
            
            applicationMenu.addItem(menuItem)
        }
        
        // 添加从 Finder 选择的选项
        applicationMenu.addItem(NSMenuItem.separator())
        let finderItem = NSMenuItem(title: NSLocalizedString("button.app.settings.select.finder", comment: ""), action: #selector(selectFromFinder(_:)), keyEquivalent: "")
        finderItem.target = self
        applicationMenu.addItem(finderItem)
        
        // 显示菜单
        let position = NSPoint(x: button.frame.origin.x, y: button.frame.origin.y - 5)
        applicationMenu.popUp(positioning: nil, at: position, in: view)
    }
    
    @objc private func addApplicationFromMenu(_ sender: NSMenuItem) {
        guard let runningApp = sender.representedObject as? NSRunningApplication,
              let executablePath = runningApp.executableURL?.path else { return }
        
        let displayName = runningApp.localizedName
        let rule = ButtonApplicationRule(applicationPath: executablePath, displayName: displayName)
        
        if currentAddTarget == "disabled" {
            disabledApplications.append(rule)
            onDisabledAppsChanged?(disabledApplications)
        } else {
            enabledApplications.append(rule)
            onEnabledAppsChanged?(enabledApplications)
        }
        updateUI()
    }
    
    @objc private func selectFromFinder(_ sender: NSMenuItem) {
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        
        openPanel.beginSheetModal(for: view.window!) { [weak self] result in
            guard result == .OK, let url = openPanel.url else { return }
            guard let self = self else { return }
            
            let path = url.path
            let displayName = Utils.getApplicationName(fromPath: path)
            let rule = ButtonApplicationRule(applicationPath: path, displayName: displayName)
            
            if self.currentAddTarget == "disabled" {
                // 检查是否已存在
                if !self.disabledApplications.contains(where: { $0.applicationPath == path }) {
                    self.disabledApplications.append(rule)
                    self.onDisabledAppsChanged?(self.disabledApplications)
                }
            } else {
                if !self.enabledApplications.contains(where: { $0.applicationPath == path }) {
                    self.enabledApplications.append(rule)
                    self.onEnabledAppsChanged?(self.enabledApplications)
                }
            }
            self.updateUI()
        }
    }
}

// MARK: - NSTableViewDelegate & NSTableViewDataSource

extension ButtonAppSettingsPopoverViewController: NSTableViewDelegate, NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView.tag == 1 {
            return disabledApplications.count
        } else {
            return enabledApplications.count
        }
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rules = tableView.tag == 1 ? disabledApplications : enabledApplications
        guard row < rules.count else { return nil }
        let rule = rules[row]
        
        let cellIdentifier = NSUserInterfaceItemIdentifier("ApplicationCell")
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView
        
        if cell == nil {
            cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            cell?.identifier = cellIdentifier
            
            let imageView = NSImageView(frame: NSRect(x: 4, y: 2, width: 20, height: 20))
            imageView.imageScaling = .scaleProportionallyDown
            cell?.addSubview(imageView)
            cell?.imageView = imageView
            
            let textField = NSTextField(labelWithString: "")
            textField.frame = NSRect(x: 28, y: 2, width: 220, height: 20)
            textField.lineBreakMode = .byTruncatingTail
            textField.font = NSFont.systemFont(ofSize: 12)
            cell?.addSubview(textField)
            cell?.textField = textField
        }
        
        cell?.imageView?.image = rule.getIcon()
        cell?.textField?.stringValue = rule.getName()
        cell?.toolTip = rule.applicationPath
        
        return cell
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        disabledRemoveButton.isEnabled = disabledTableView.selectedRow != -1
        enabledRemoveButton.isEnabled = enabledTableView.selectedRow != -1
    }
}
