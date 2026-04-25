//
//  PreferencesViewController.swift
//  Mos
//  基础选项界面
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {
    
    // UI Elements
    @IBOutlet weak var launchOnLoginCheckBox: NSButton!
    @IBOutlet weak var hideStatusBarIconCheckBox: NSButton!
    
    // Mouse Sensitivity UI Elements (created programmatically)
    private var mouseSensitivityCheckBox: NSButton!
    private var mouseSensitivityLabel: NSTextField!
    private var mouseSensitivitySlider: NSSlider!
    private var mouseSensitivityInput: NSTextField!
    private var mouseSensitivityStepper: NSStepper!
    private var mouseSensitivityValueLabel: NSTextField!
    
    // Backup/Restore UI Elements
    private var exportSettingsButton: NSButton!
    private var importSettingsButton: NSButton!
    
    // Layout constraints
    private var dynamicConstraints: [NSLayoutConstraint] = []
    
    // Separators (kept as properties to prevent deallocation)
    private var separator1: NSBox!
    private var separator2: NSBox!
    private var backupLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 创建动态 UI 元素
        createMouseSensitivityUI()
        createBackupUI()
        // 读取设置
        syncViewWithOptions()
    }
    
    // 创建鼠标灵敏度设置 UI
    private func createMouseSensitivityUI() {
        // 分隔线
        separator1 = NSBox()
        separator1.boxType = .separator
        separator1.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator1)
        
        // 鼠标灵敏度复选框
        mouseSensitivityCheckBox = NSButton(checkboxWithTitle: NSLocalizedString("Enable Mouse Sensitivity Adjustment", comment: "Enable mouse sensitivity adjustment"), target: self, action: #selector(mouseSensitivityCheckBoxClick(_:)))
        mouseSensitivityCheckBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mouseSensitivityCheckBox)
        
        // 鼠标灵敏度标签
        mouseSensitivityLabel = NSTextField(labelWithString: NSLocalizedString("Mouse Sensitivity", comment: "Mouse sensitivity"))
        mouseSensitivityLabel.translatesAutoresizingMaskIntoConstraints = false
        mouseSensitivityLabel.isBezeled = false
        mouseSensitivityLabel.isEditable = false
        mouseSensitivityLabel.drawsBackground = false
        view.addSubview(mouseSensitivityLabel)
        
        // 鼠标灵敏度滑块
        mouseSensitivitySlider = NSSlider(value: 1.0, minValue: 0.1, maxValue: 5.0, target: self, action: #selector(mouseSensitivitySliderChange(_:)))
        mouseSensitivitySlider.translatesAutoresizingMaskIntoConstraints = false
        // 注意: allowsTickMarks 是 macOS 10.15+ 的 API，为了兼容 macOS 10.13
        // 在旧版本中，设置 numberOfTickMarks 就会自动显示刻度标记
        mouseSensitivitySlider.numberOfTickMarks = 10
        view.addSubview(mouseSensitivitySlider)
        
        // 鼠标灵敏度输入框
        mouseSensitivityInput = NSTextField(string: "1.00")
        mouseSensitivityInput.translatesAutoresizingMaskIntoConstraints = false
        mouseSensitivityInput.delegate = self
        mouseSensitivityInput.refusesFirstResponder = true
        mouseSensitivityInput.alignment = .center
        mouseSensitivityInput.formatter = NumberFormatter()
        if let formatter = mouseSensitivityInput.formatter as? NumberFormatter {
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            formatter.minimum = 0.1
            formatter.maximum = 5.0
        }
        view.addSubview(mouseSensitivityInput)
        
        // 鼠标灵敏度值标签 (显示当前值)
        mouseSensitivityValueLabel = NSTextField(labelWithString: "1.00x")
        mouseSensitivityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        mouseSensitivityValueLabel.isBezeled = false
        mouseSensitivityValueLabel.isEditable = false
        mouseSensitivityValueLabel.drawsBackground = false
        mouseSensitivityValueLabel.alignment = .center
        mouseSensitivityValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        view.addSubview(mouseSensitivityValueLabel)
        
        // 布局约束
        NSLayoutConstraint.activate([
            separator1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            separator1.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            separator1.topAnchor.constraint(equalTo: hideStatusBarIconCheckBox.bottomAnchor, constant: 20),
            
            mouseSensitivityCheckBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mouseSensitivityCheckBox.topAnchor.constraint(equalTo: separator1.bottomAnchor, constant: 20),
            
            mouseSensitivityLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mouseSensitivityLabel.topAnchor.constraint(equalTo: mouseSensitivityCheckBox.bottomAnchor, constant: 16),
            mouseSensitivityLabel.widthAnchor.constraint(equalToConstant: 120),
            
            mouseSensitivitySlider.leadingAnchor.constraint(equalTo: mouseSensitivityLabel.trailingAnchor, constant: 8),
            mouseSensitivitySlider.centerYAnchor.constraint(equalTo: mouseSensitivityLabel.centerYAnchor),
            mouseSensitivitySlider.widthAnchor.constraint(equalToConstant: 200),
            
            mouseSensitivityValueLabel.leadingAnchor.constraint(equalTo: mouseSensitivitySlider.trailingAnchor, constant: 12),
            mouseSensitivityValueLabel.centerYAnchor.constraint(equalTo: mouseSensitivityLabel.centerYAnchor),
            mouseSensitivityValueLabel.widthAnchor.constraint(equalToConstant: 60),
        ])
    }
    
    // 创建备份/恢复 UI
    private func createBackupUI() {
        // 分隔线
        separator2 = NSBox()
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator2)
        
        // 备份/恢复标签
        backupLabel = NSTextField(labelWithString: NSLocalizedString("Settings Backup", comment: "Settings backup"))
        backupLabel.translatesAutoresizingMaskIntoConstraints = false
        backupLabel.isBezeled = false
        backupLabel.isEditable = false
        backupLabel.drawsBackground = false
        backupLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        view.addSubview(backupLabel)
        
        // 导出设置按钮
        exportSettingsButton = NSButton(title: NSLocalizedString("Export Settings", comment: "Export settings"), target: self, action: #selector(exportSettingsClick(_:)))
        exportSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        exportSettingsButton.bezelStyle = .rounded
        view.addSubview(exportSettingsButton)
        
        // 导入设置按钮
        importSettingsButton = NSButton(title: NSLocalizedString("Import Settings", comment: "Import settings"), target: self, action: #selector(importSettingsClick(_:)))
        importSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        importSettingsButton.bezelStyle = .rounded
        view.addSubview(importSettingsButton)
        
        // 布局约束
        NSLayoutConstraint.activate([
            separator2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            separator2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            separator2.topAnchor.constraint(equalTo: mouseSensitivitySlider.bottomAnchor, constant: 24),
            
            backupLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            backupLabel.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: 20),
            
            exportSettingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            exportSettingsButton.topAnchor.constraint(equalTo: backupLabel.bottomAnchor, constant: 12),
            exportSettingsButton.widthAnchor.constraint(equalToConstant: 120),
            
            importSettingsButton.leadingAnchor.constraint(equalTo: exportSettingsButton.trailingAnchor, constant: 12),
            importSettingsButton.topAnchor.constraint(equalTo: exportSettingsButton.topAnchor),
            importSettingsButton.widthAnchor.constraint(equalToConstant: 120),
        ])
        
        // 设置视图的底部约束，确保窗口可以正确调整大小
        let bottomConstraint = view.bottomAnchor.constraint(greaterThanOrEqualTo: exportSettingsButton.bottomAnchor, constant: 20)
        bottomConstraint.priority = .defaultHigh
        bottomConstraint.isActive = true
    }
    
    // 自启
    @IBAction func launchOnLoginClick(_ sender: NSButton) {
        Options.shared.general.autoLaunch = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 隐藏
    @IBAction func hideStatusBarIconClick(_ sender: NSButton) {
        Options.shared.general.hideStatusItem = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 鼠标灵敏度启用/禁用
    @objc func mouseSensitivityCheckBoxClick(_ sender: NSButton) {
        Options.shared.mouse.enableSensitivity = sender.state.rawValue != 0
        MouseSensitivityManager.shared.refresh()
        syncViewWithOptions()
    }
    
    // 鼠标灵敏度滑块变化
    @objc func mouseSensitivitySliderChange(_ sender: NSSlider) {
        setMouseSensitivity(value: sender.doubleValue)
    }
    
    // 设置鼠标灵敏度
    func setMouseSensitivity(value: Double) {
        let clampedValue = max(0.1, min(5.0, value))
        Options.shared.mouse.sensitivity = clampedValue
        syncViewWithOptions()
    }
    
    // 导出设置
    @objc func exportSettingsClick(_ sender: NSButton) {
        SettingsBackupManager.shared.exportSettings()
    }
    
    // 导入设置
    @objc func importSettingsClick(_ sender: NSButton) {
        if SettingsBackupManager.shared.importSettings() {
            syncViewWithOptions()
        }
    }
}

/**
 * 设置同步
 **/
extension PreferencesGeneralViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 自启
        launchOnLoginCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.autoLaunch ? 1 : 0)
        // 隐藏
        hideStatusBarIconCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.hideStatusItem ? 1 : 0)
        
        // 鼠标灵敏度
        let enableSensitivity = Options.shared.mouse.enableSensitivity
        mouseSensitivityCheckBox.state = NSControl.StateValue(rawValue: enableSensitivity ? 1 : 0)
        
        let sensitivity = Options.shared.mouse.sensitivity
        mouseSensitivitySlider.doubleValue = sensitivity
        mouseSensitivitySlider.isEnabled = enableSensitivity
        mouseSensitivityInput.stringValue = String(format: "%.2f", sensitivity)
        mouseSensitivityValueLabel.stringValue = String(format: "%.2fx", sensitivity)
        
        mouseSensitivityLabel.textColor = enableSensitivity ? NSColor.controlTextColor : NSColor.disabledControlTextColor
    }
}

/**
 * NSTextFieldDelegate
 **/
extension PreferencesGeneralViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        
        if textField === mouseSensitivityInput {
            if let value = Double(textField.stringValue) {
                setMouseSensitivity(value: value)
            } else {
                syncViewWithOptions()
            }
        }
    }
}
