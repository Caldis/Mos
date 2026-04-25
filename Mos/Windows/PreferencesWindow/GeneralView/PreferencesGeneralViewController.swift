//
//  PreferencesViewController.swift
//  Mos
//  基础选项界面
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {
    
    // UI Elements from Storyboard
    @IBOutlet weak var launchOnLoginCheckBox: NSButton!
    @IBOutlet weak var hideStatusBarIconCheckBox: NSButton!
    
    // MARK: - Dynamic UI Elements (created programmatically)
    // Container stack view for all dynamic elements
    private var containerStackView: NSStackView!
    
    // Mouse Sensitivity UI Elements
    private var separator1: NSBox!
    private var mouseSensitivityCheckBox: NSButton!
    private var mouseSensitivityRowStack: NSStackView!
    private var mouseSensitivityLabel: NSTextField!
    private var mouseSensitivitySlider: NSSlider!
    private var mouseSensitivityValueLabel: NSTextField!
    
    // Backup/Restore UI Elements
    private var separator2: NSBox!
    private var backupLabel: NSTextField!
    private var backupButtonsStack: NSStackView!
    private var exportSettingsButton: NSButton!
    private var importSettingsButton: NSButton!
    
    // Bottom spacer
    private var bottomSpacer: NSView!
    
    // Track if UI has been set up
    private var isUISetup = false
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Setup UI once
        setupDynamicUI()
        // Sync with options
        syncViewWithOptions()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        // Ensure UI is synced when view appears
        syncViewWithOptions()
    }
    
    // MARK: - Dynamic UI Setup
    private func setupDynamicUI() {
        guard !isUISetup else { return }
        isUISetup = true
        
        // Create all UI elements
        createSeparator1()
        createMouseSensitivitySection()
        createSeparator2()
        createBackupSection()
        createBottomSpacer()
        
        // Create main container stack view
        containerStackView = NSStackView()
        containerStackView.orientation = .vertical
        containerStackView.alignment = .leading
        containerStackView.spacing = 0
        containerStackView.distribution = .fill
        containerStackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add elements to stack view with custom spacing
        containerStackView.addArrangedSubview(separator1)
        containerStackView.setCustomSpacing(16, after: separator1)
        
        containerStackView.addArrangedSubview(mouseSensitivityCheckBox)
        containerStackView.setCustomSpacing(12, after: mouseSensitivityCheckBox)
        
        containerStackView.addArrangedSubview(mouseSensitivityRowStack)
        containerStackView.setCustomSpacing(24, after: mouseSensitivityRowStack)
        
        containerStackView.addArrangedSubview(separator2)
        containerStackView.setCustomSpacing(16, after: separator2)
        
        containerStackView.addArrangedSubview(backupLabel)
        containerStackView.setCustomSpacing(12, after: backupLabel)
        
        containerStackView.addArrangedSubview(backupButtonsStack)
        
        containerStackView.addArrangedSubview(bottomSpacer)
        
        // Add stack view to main view
        view.addSubview(containerStackView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Position stack view below hideStatusBarIconCheckBox
            separator1.widthAnchor.constraint(equalTo: containerStackView.widthAnchor),
            separator2.widthAnchor.constraint(equalTo: containerStackView.widthAnchor),
            
            // Stack view constraints - pin to left/right, and below last existing element
            containerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            containerStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            containerStackView.topAnchor.constraint(equalTo: hideStatusBarIconCheckBox.bottomAnchor, constant: 20),
            
            // Bottom constraint - this is crucial for the view to have a proper height
            // Use a low priority constraint to allow flexibility, but still provide a baseline
            containerStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        ])
        
        // Set hugging priority and compression resistance
        containerStackView.setHuggingPriority(.required, for: .vertical)
        containerStackView.setCompressionResistancePriority(.required, for: .vertical)
    }
    
    private func createSeparator1() {
        separator1 = NSBox()
        separator1.boxType = .separator
        separator1.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func createMouseSensitivitySection() {
        // Checkbox
        mouseSensitivityCheckBox = NSButton(
            checkboxWithTitle: NSLocalizedString("Enable Mouse Sensitivity Adjustment", comment: "Enable mouse sensitivity adjustment"),
            target: self,
            action: #selector(mouseSensitivityCheckBoxClick(_:))
        )
        mouseSensitivityCheckBox.translatesAutoresizingMaskIntoConstraints = false
        
        // Row stack view for sensitivity controls
        mouseSensitivityRowStack = NSStackView()
        mouseSensitivityRowStack.orientation = .horizontal
        mouseSensitivityRowStack.alignment = .centerY
        mouseSensitivityRowStack.spacing = 8
        mouseSensitivityRowStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Label
        mouseSensitivityLabel = NSTextField(labelWithString: NSLocalizedString("Mouse Sensitivity", comment: "Mouse sensitivity"))
        mouseSensitivityLabel.translatesAutoresizingMaskIntoConstraints = false
        mouseSensitivityLabel.isBezeled = false
        mouseSensitivityLabel.isEditable = false
        mouseSensitivityLabel.drawsBackground = false
        mouseSensitivityLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        // Slider
        mouseSensitivitySlider = NSSlider(value: 1.0, minValue: 0.1, maxValue: 5.0, target: self, action: #selector(mouseSensitivitySliderChange(_:)))
        mouseSensitivitySlider.translatesAutoresizingMaskIntoConstraints = false
        mouseSensitivitySlider.numberOfTickMarks = 10
        mouseSensitivitySlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mouseSensitivitySlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // Value label
        mouseSensitivityValueLabel = NSTextField(labelWithString: "1.00x")
        mouseSensitivityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        mouseSensitivityValueLabel.isBezeled = false
        mouseSensitivityValueLabel.isEditable = false
        mouseSensitivityValueLabel.drawsBackground = false
        mouseSensitivityValueLabel.alignment = .center
        mouseSensitivityValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        mouseSensitivityValueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        mouseSensitivityValueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        
        // Add to row stack
        mouseSensitivityRowStack.addArrangedSubview(mouseSensitivityLabel)
        mouseSensitivityRowStack.addArrangedSubview(mouseSensitivitySlider)
        mouseSensitivityRowStack.addArrangedSubview(mouseSensitivityValueLabel)
        
        // Set slider width constraint
        mouseSensitivitySlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
    }
    
    private func createSeparator2() {
        separator2 = NSBox()
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func createBackupSection() {
        // Label
        backupLabel = NSTextField(labelWithString: NSLocalizedString("Settings Backup", comment: "Settings backup"))
        backupLabel.translatesAutoresizingMaskIntoConstraints = false
        backupLabel.isBezeled = false
        backupLabel.isEditable = false
        backupLabel.drawsBackground = false
        backupLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        
        // Buttons stack view
        backupButtonsStack = NSStackView()
        backupButtonsStack.orientation = .horizontal
        backupButtonsStack.alignment = .centerY
        backupButtonsStack.spacing = 12
        backupButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Export button
        exportSettingsButton = NSButton(
            title: NSLocalizedString("Export Settings", comment: "Export settings"),
            target: self,
            action: #selector(exportSettingsClick(_:))
        )
        exportSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        exportSettingsButton.bezelStyle = .rounded
        exportSettingsButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        exportSettingsButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        
        // Import button
        importSettingsButton = NSButton(
            title: NSLocalizedString("Import Settings", comment: "Import settings"),
            target: self,
            action: #selector(importSettingsClick(_:))
        )
        importSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        importSettingsButton.bezelStyle = .rounded
        importSettingsButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        importSettingsButton.widthAnchor.constraint(equalToConstant: 120).isActive = true
        
        // Add to buttons stack
        backupButtonsStack.addArrangedSubview(exportSettingsButton)
        backupButtonsStack.addArrangedSubview(importSettingsButton)
    }
    
    private func createBottomSpacer() {
        bottomSpacer = NSView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        bottomSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
    }
    
    // MARK: - Actions
    @IBAction func launchOnLoginClick(_ sender: NSButton) {
        Options.shared.general.autoLaunch = sender.state.rawValue == 0 ? false : true
        syncViewWithOptions()
    }
    
    @IBAction func hideStatusBarIconClick(_ sender: NSButton) {
        Options.shared.general.hideStatusItem = sender.state.rawValue == 0 ? false : true
        syncViewWithOptions()
    }
    
    @objc func mouseSensitivityCheckBoxClick(_ sender: NSButton) {
        Options.shared.mouse.enableSensitivity = sender.state.rawValue != 0
        MouseSensitivityManager.shared.refresh()
        syncViewWithOptions()
    }
    
    @objc func mouseSensitivitySliderChange(_ sender: NSSlider) {
        setMouseSensitivity(value: sender.doubleValue)
    }
    
    func setMouseSensitivity(value: Double) {
        let clampedValue = max(0.1, min(5.0, value))
        Options.shared.mouse.sensitivity = clampedValue
        syncViewWithOptions()
    }
    
    @objc func exportSettingsClick(_ sender: NSButton) {
        SettingsBackupManager.shared.exportSettings()
    }
    
    @objc func importSettingsClick(_ sender: NSButton) {
        if SettingsBackupManager.shared.importSettings() {
            syncViewWithOptions()
        }
    }
}

// MARK: - UI Synchronization
extension PreferencesGeneralViewController {
    func syncViewWithOptions() {
        // Storyboard elements
        launchOnLoginCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.autoLaunch ? 1 : 0)
        hideStatusBarIconCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.hideStatusItem ? 1 : 0)
        
        // Dynamic elements - only sync if UI is setup
        guard isUISetup else { return }
        
        let enableSensitivity = Options.shared.mouse.enableSensitivity
        let sensitivity = Options.shared.mouse.sensitivity
        
        // Update mouse sensitivity UI
        mouseSensitivityCheckBox.state = NSControl.StateValue(rawValue: enableSensitivity ? 1 : 0)
        mouseSensitivitySlider.doubleValue = sensitivity
        mouseSensitivitySlider.isEnabled = enableSensitivity
        mouseSensitivityValueLabel.stringValue = String(format: "%.2fx", sensitivity)
        
        // Update label text color
        mouseSensitivityLabel.textColor = enableSensitivity ? NSColor.controlTextColor : NSColor.disabledControlTextColor
    }
}
