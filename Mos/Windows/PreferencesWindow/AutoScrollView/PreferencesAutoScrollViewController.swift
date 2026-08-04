//
//  PreferencesAutoScrollViewController.swift
//  Mos
//  自动滚动选项界面
//  Created by Auto-Scroll Implementation on 2025/11/29.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAutoScrollViewController: NSViewController {

    // MARK: - UI Elements

    // Enable/Disable toggle
    private var enabledCheckBox: NSButton!

    // Dark mode toggle
    private var darkModeCheckBox: NSButton!

    // Sensitivity slider (0.2x - 3.0x)
    private var sensitivitySlider: NSSlider!
    private var sensitivityLabel: NSTextField!
    private var sensitivityValueLabel: NSTextField!

    // Dead zone slider (0-20px)
    private var deadZoneSlider: NSSlider!
    private var deadZoneLabel: NSTextField!
    private var deadZoneValueLabel: NSTextField!

    // Drag threshold slider (5-30px)
    private var dragThresholdSlider: NSSlider!
    private var dragThresholdLabel: NSTextField!
    private var dragThresholdValueLabel: NSTextField!

    // Max speed slider (10-100px)
    private var maxSpeedSlider: NSSlider!
    private var maxSpeedLabel: NSTextField!
    private var maxSpeedValueLabel: NSTextField!

    // Activation button selector
    private var activationButtonPopup: NSPopUpButton!
    private var activationButtonLabel: NSTextField!

    // Info text
    private var infoTextView: NSTextField!

    // Reset button
    private var resetButton: NSButton!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        // Setup UI when view is about to appear (ensures view is fully loaded)
        if enabledCheckBox == nil {
            setupUI()
            syncViewWithOptions()
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard view.bounds.height > 0 else { return }
        var yPosition: CGFloat = view.bounds.height - 30

        // Title
        let titleLabel = createLabel(
            text: NSLocalizedString("Auto-Scroll Settings", comment: "Auto-scroll preferences title"),
            fontSize: 18,
            bold: true
        )
        titleLabel.frame = NSRect(x: 20, y: yPosition, width: 560, height: 25)
        view.addSubview(titleLabel)
        yPosition -= 35

        // Info text
        infoTextView = createLabel(
            text: NSLocalizedString("Configure auto-scrolling when middle-clicking.", comment: "Auto-scroll info"),
            fontSize: 11,
            bold: false
        )
        infoTextView.textColor = .secondaryLabelColor
        infoTextView.frame = NSRect(x: 20, y: yPosition, width: 560, height: 20)
        view.addSubview(infoTextView)
        yPosition -= 28

        // Enabled checkbox
        enabledCheckBox = NSButton(checkboxWithTitle: NSLocalizedString("Enable Auto-Scroll", comment: "Enable auto-scroll"), target: self, action: #selector(enabledChanged))
        enabledCheckBox.frame = NSRect(x: 20, y: yPosition, width: 200, height: 22)
        view.addSubview(enabledCheckBox)
        yPosition -= 25

        // Dark mode checkbox
        darkModeCheckBox = NSButton(checkboxWithTitle: NSLocalizedString("White Background (dark mode)", comment: "Dark mode icon"), target: self, action: #selector(darkModeChanged))
        darkModeCheckBox.frame = NSRect(x: 20, y: yPosition, width: 250, height: 22)
        view.addSubview(darkModeCheckBox)
        yPosition -= 32

        // Separator
        let separator1 = NSBox()
        separator1.boxType = .separator
        separator1.frame = NSRect(x: 20, y: yPosition, width: 560, height: 1)
        view.addSubview(separator1)
        yPosition -= 25

        // Sensitivity slider
        sensitivityLabel = createLabel(text: NSLocalizedString("Scroll Speed Sensitivity:", comment: ""), fontSize: 13, bold: false)
        sensitivityLabel.frame = NSRect(x: 20, y: yPosition, width: 200, height: 20)
        view.addSubview(sensitivityLabel)

        sensitivityValueLabel = createLabel(text: "1.0x", fontSize: 13, bold: false)
        sensitivityValueLabel.alignment = .right
        sensitivityValueLabel.frame = NSRect(x: 520, y: yPosition, width: 60, height: 20)
        view.addSubview(sensitivityValueLabel)
        yPosition -= 25

        sensitivitySlider = NSSlider(value: 1.0, minValue: 0.2, maxValue: 3.0, target: self, action: #selector(sensitivityChanged))
        sensitivitySlider.frame = NSRect(x: 20, y: yPosition, width: 560, height: 22)
        view.addSubview(sensitivitySlider)
        yPosition -= 30

        // Dead zone slider
        deadZoneLabel = createLabel(text: NSLocalizedString("Dead Zone (no scroll near origin):", comment: ""), fontSize: 13, bold: false)
        deadZoneLabel.frame = NSRect(x: 20, y: yPosition, width: 250, height: 20)
        view.addSubview(deadZoneLabel)

        deadZoneValueLabel = createLabel(text: "5 px", fontSize: 13, bold: false)
        deadZoneValueLabel.alignment = .right
        deadZoneValueLabel.frame = NSRect(x: 520, y: yPosition, width: 60, height: 20)
        view.addSubview(deadZoneValueLabel)
        yPosition -= 25

        deadZoneSlider = NSSlider(value: 5.0, minValue: 0.0, maxValue: 20.0, target: self, action: #selector(deadZoneChanged))
        deadZoneSlider.frame = NSRect(x: 20, y: yPosition, width: 560, height: 22)
        view.addSubview(deadZoneSlider)
        yPosition -= 30

        // Drag threshold slider
        dragThresholdLabel = createLabel(text: NSLocalizedString("Drag Threshold (click vs drag):", comment: ""), fontSize: 13, bold: false)
        dragThresholdLabel.frame = NSRect(x: 20, y: yPosition, width: 250, height: 20)
        view.addSubview(dragThresholdLabel)

        dragThresholdValueLabel = createLabel(text: "10 px", fontSize: 13, bold: false)
        dragThresholdValueLabel.alignment = .right
        dragThresholdValueLabel.frame = NSRect(x: 520, y: yPosition, width: 60, height: 20)
        view.addSubview(dragThresholdValueLabel)
        yPosition -= 25

        dragThresholdSlider = NSSlider(value: 10.0, minValue: 5.0, maxValue: 30.0, target: self, action: #selector(dragThresholdChanged))
        dragThresholdSlider.frame = NSRect(x: 20, y: yPosition, width: 560, height: 22)
        view.addSubview(dragThresholdSlider)
        yPosition -= 30

        // Max speed slider
        maxSpeedLabel = createLabel(text: NSLocalizedString("Maximum Scroll Speed:", comment: ""), fontSize: 13, bold: false)
        maxSpeedLabel.frame = NSRect(x: 20, y: yPosition, width: 200, height: 20)
        view.addSubview(maxSpeedLabel)

        maxSpeedValueLabel = createLabel(text: "30 px", fontSize: 13, bold: false)
        maxSpeedValueLabel.alignment = .right
        maxSpeedValueLabel.frame = NSRect(x: 520, y: yPosition, width: 60, height: 20)
        view.addSubview(maxSpeedValueLabel)
        yPosition -= 25

        maxSpeedSlider = NSSlider(value: 30.0, minValue: 10.0, maxValue: 100.0, target: self, action: #selector(maxSpeedChanged))
        maxSpeedSlider.frame = NSRect(x: 20, y: yPosition, width: 560, height: 22)
        view.addSubview(maxSpeedSlider)
        yPosition -= 32

        // Separator
        let separator2 = NSBox()
        separator2.boxType = .separator
        separator2.frame = NSRect(x: 20, y: yPosition, width: 560, height: 1)
        view.addSubview(separator2)
        yPosition -= 28

        // Activation button
        activationButtonLabel = createLabel(text: NSLocalizedString("Activation Button:", comment: ""), fontSize: 13, bold: false)
        activationButtonLabel.frame = NSRect(x: 20, y: yPosition, width: 150, height: 20)
        view.addSubview(activationButtonLabel)

        activationButtonPopup = NSPopUpButton(frame: NSRect(x: 180, y: yPosition - 2, width: 200, height: 26), pullsDown: false)
        activationButtonPopup.addItems(withTitles: ["Middle Button (Button 2)", "Side Button 1 (Button 3)", "Side Button 2 (Button 4)"])
        activationButtonPopup.target = self
        activationButtonPopup.action = #selector(activationButtonChanged)
        view.addSubview(activationButtonPopup)
        yPosition -= 40

        // Reset button
        resetButton = NSButton(title: NSLocalizedString("Reset to Defaults", comment: ""), target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 20, y: yPosition, width: 150, height: 28)
        view.addSubview(resetButton)

        NSLog("[AutoScroll Prefs] Final yPosition: \(yPosition), view height: \(view.bounds.height)")
    }

    private func createLabel(text: String, fontSize: CGFloat, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.backgroundColor = .clear
        return label
    }

    // MARK: - Sync with Options

    private func syncViewWithOptions() {
        let options = Options.shared.autoScroll

        enabledCheckBox.state = options.enabled ? .on : .off
        darkModeCheckBox.state = options.darkMode ? .on : .off

        sensitivitySlider.doubleValue = options.sensitivity
        sensitivityValueLabel.stringValue = String(format: "%.1fx", options.sensitivity)

        deadZoneSlider.doubleValue = Double(options.deadZone)
        deadZoneValueLabel.stringValue = String(format: "%.0f px", options.deadZone)

        dragThresholdSlider.doubleValue = Double(options.dragThreshold)
        dragThresholdValueLabel.stringValue = String(format: "%.0f px", options.dragThreshold)

        maxSpeedSlider.doubleValue = Double(options.maxSpeed)
        maxSpeedValueLabel.stringValue = String(format: "%.0f px", options.maxSpeed)

        // Activation button (2 = middle, 3 = side1, 4 = side2)
        let buttonIndex = options.activationButton - 2
        if buttonIndex >= 0 && buttonIndex < activationButtonPopup.numberOfItems {
            activationButtonPopup.selectItem(at: buttonIndex)
        }

        // Enable/disable controls based on enabled state
        let isEnabled = options.enabled
        sensitivitySlider.isEnabled = isEnabled
        deadZoneSlider.isEnabled = isEnabled
        dragThresholdSlider.isEnabled = isEnabled
        maxSpeedSlider.isEnabled = isEnabled
        activationButtonPopup.isEnabled = isEnabled
    }

    // MARK: - Actions

    @objc private func enabledChanged() {
        Options.shared.autoScroll.enabled = enabledCheckBox.state == .on
        syncViewWithOptions()
    }

    @objc private func darkModeChanged() {
        Options.shared.autoScroll.darkMode = darkModeCheckBox.state == .on
    }

    @objc private func sensitivityChanged() {
        let value = sensitivitySlider.doubleValue
        Options.shared.autoScroll.sensitivity = AutoScrollUtils.validateSensitivity(value)
        sensitivityValueLabel.stringValue = String(format: "%.1fx", value)
    }

    @objc private func deadZoneChanged() {
        let value = CGFloat(deadZoneSlider.doubleValue)
        Options.shared.autoScroll.deadZone = AutoScrollUtils.validateDeadZone(value)
        deadZoneValueLabel.stringValue = String(format: "%.0f px", value)
    }

    @objc private func dragThresholdChanged() {
        let value = CGFloat(dragThresholdSlider.doubleValue)
        Options.shared.autoScroll.dragThreshold = AutoScrollUtils.validateDragThreshold(value)
        dragThresholdValueLabel.stringValue = String(format: "%.0f px", value)
    }

    @objc private func maxSpeedChanged() {
        let value = CGFloat(maxSpeedSlider.doubleValue)
        Options.shared.autoScroll.maxSpeed = AutoScrollUtils.validateMaxSpeed(value)
        maxSpeedValueLabel.stringValue = String(format: "%.0f px", value)
    }

    @objc private func activationButtonChanged() {
        // Map popup index to button number (0->2, 1->3, 2->4)
        Options.shared.autoScroll.activationButton = activationButtonPopup.indexOfSelectedItem + 2
    }

    @objc private func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Reset Auto-Scroll Settings?", comment: "")
        alert.informativeText = NSLocalizedString("This will reset all auto-scroll settings to their default values.", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Reset", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            // Reset to default values
            Options.shared.autoScroll.enabled = true
            Options.shared.autoScroll.sensitivity = 1.0
            Options.shared.autoScroll.deadZone = 5.0
            Options.shared.autoScroll.dragThreshold = 10.0
            Options.shared.autoScroll.maxSpeed = 30.0
            Options.shared.autoScroll.activationButton = 2
            Options.shared.autoScroll.darkMode = false
            Options.shared.autoScroll.appExceptions = []
            syncViewWithOptions()
        }
    }
}
