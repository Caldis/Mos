//
//  ToastPanel.swift
//  Mos
//  产品级 Toast Debug 面板 - 配置、自定义发送、场景测试
//

import Cocoa

/// Toast Debug 面板
///
/// 面向用户的产品功能, 提供 Toast 配置、自定义发送和一键场景测试。
/// 作为 NSObject 子类可直接作为 NSMenuItem 的 target。
class ToastPanel: NSObject {

    private struct LayoutMetrics {
        static let panelWidth: CGFloat = 420
        static let horizontalMargin: CGFloat = 20
        static let topPadding: CGFloat = 12
        static let bottomPadding: CGFloat = 20
        static let titleHeight: CGFloat = 22
        static let subtitleHeight: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let rowHeight: CGFloat = 18
        static let fieldHeight: CGFloat = 22
        static let buttonHeight: CGFloat = 24
        static let resetButtonHeight: CGFloat = 22
        static let gridCellHeight: CGFloat = 36
        static let gridCellSpacing: CGFloat = 6
        static let gridColumnSpacing: CGFloat = 8
        static let labelColumnWidth: CGFloat = 140
        static let valueColumnX: CGFloat = horizontalMargin + 180
    }

    static let shared = ToastPanel()

    private var window: NSPanel?

    // MARK: - UI Controls (Configuration)
    private var maxCountSlider: NSSlider!
    private var maxCountLabel: NSTextField!
    private var wrapWidthField: NSTextField!
    private var positionStatusLabel: NSTextField!

    // MARK: - UI Controls (Send Toast)
    private var messageField: NSTextField!
    private var styleButtons: [NSButton] = []
    private var selectedStyle: Toast.Style = .info
    private var durationSlider: NSSlider!
    private var durationLabel: NSTextField!
    private var showsIconCheckbox: NSButton!
    private var useCustomIconCheckbox: NSButton!
    private var showsAccentRibbonCheckbox: NSButton!

    private let positionStatusActiveColor = NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0)

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anchorDidChange),
            name: .toastAnchorDidChange,
            object: nil
        )
    }

    // MARK: - Menu Item

    /// 创建可直接加入菜单的 MenuItem
    func createMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("Toast Debug", comment: "Toast debug panel menu item"),
            action: #selector(menuItemClicked),
            keyEquivalent: ""
        )
        item.target = self
        if #available(macOS 11.0, *) {
            if let img = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil) {
                img.isTemplate = true
                item.image = img
            }
        } else {
            item.image = #imageLiteral(resourceName: "SF.bubble.left.fill")
        }
        return item
    }

    @objc private func menuItemClicked() {
        show()
    }

    // MARK: - Show

    func show() {
        if let w = window {
            refreshPositionStatus()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            applyAccentRibbonPreference()
            applyIconPreference()
            applyWrapWidthPreference()
            return
        }
        let w = buildWindow()
        window = w
        refreshPositionStatus()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyAccentRibbonPreference()
        applyIconPreference()
        applyWrapWidthPreference()
    }

    // MARK: - Build Window

    private func buildWindow() -> NSPanel {
        // Initial height — will be adjusted by Auto Layout via bottom constraint
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: LayoutMetrics.panelWidth, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = NSLocalizedString("Toast Debug", comment: "Toast debug panel window title")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let effectView = NSVisualEffectView(frame: panel.contentView!.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.state = .active
        effectView.blendingMode = .behindWindow

        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
            panel.appearance = NSAppearance(named: .vibrantDark)
        } else {
            effectView.material = .dark
        }
        panel.contentView = effectView

        let topInset = resolvedTopInset(for: panel)
        buildContent(in: effectView, topInset: topInset)

        // Let constraints determine the ideal height, then resize window
        effectView.layoutSubtreeIfNeeded()
        let fittingSize = effectView.fittingSize
        if fittingSize.height > 0 {
            panel.setContentSize(NSSize(width: LayoutMetrics.panelWidth, height: fittingSize.height))
        }
        panel.center()

        return panel
    }

    private func buildContent(in container: NSView, topInset: CGFloat) {
        let M = LayoutMetrics.self
        let cw = M.panelWidth - M.horizontalMargin * 2  // content width

        // All views use Auto Layout
        func pin(_ v: NSView) { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
        func h(_ v: NSView, _ height: CGFloat) { v.heightAnchor.constraint(equalToConstant: height).isActive = true }
        func lr(_ v: NSView) {
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.horizontalMargin).isActive = true
            v.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -M.horizontalMargin).isActive = true
        }

        // --- Header ---
        let titleLabel = makeLabel(text: NSLocalizedString("Toast Debug", comment: "Toast debug panel title"), fontSize: 18, weight: .semibold, color: .white)
        pin(titleLabel); lr(titleLabel); h(titleLabel, M.titleHeight)
        titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: topInset).isActive = true

        let subtitleLabel = makeLabel(text: NSLocalizedString("Component testing & configuration", comment: "Toast debug panel subtitle"), fontSize: 12, weight: .regular, color: .secondaryLabelColor)
        pin(subtitleLabel); lr(subtitleLabel); h(subtitleLabel, M.subtitleHeight)
        subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2).isActive = true

        // --- CONFIGURATION ---
        let cfgHeader = makeLabel(text: NSLocalizedString("CONFIGURATION", comment: "Toast debug section header"), fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
        pin(cfgHeader); lr(cfgHeader); h(cfgHeader, 14)
        cfgHeader.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: M.sectionSpacing).isActive = true

        // Max Simultaneous row
        let maxCountRow = makeLabel(text: NSLocalizedString("Max Simultaneous", comment: "Toast debug max count label"), fontSize: 12, weight: .regular, color: .labelColor)
        pin(maxCountRow); h(maxCountRow, M.rowHeight)
        maxCountRow.topAnchor.constraint(equalTo: cfgHeader.bottomAnchor, constant: 8).isActive = true
        maxCountRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.horizontalMargin).isActive = true
        maxCountRow.widthAnchor.constraint(equalToConstant: M.labelColumnWidth).isActive = true

        maxCountSlider = NSSlider()
        maxCountSlider.minValue = 1; maxCountSlider.maxValue = 8
        maxCountSlider.integerValue = ToastStorage.shared.maxCount
        maxCountSlider.target = self; maxCountSlider.action = #selector(maxCountChanged)
        pin(maxCountSlider); h(maxCountSlider, M.rowHeight)
        maxCountSlider.topAnchor.constraint(equalTo: maxCountRow.topAnchor).isActive = true
        maxCountSlider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.valueColumnX).isActive = true
        maxCountSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true

        maxCountLabel = makeLabel(text: "\(ToastStorage.shared.maxCount)", fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        maxCountLabel.alignment = .right
        pin(maxCountLabel); h(maxCountLabel, M.rowHeight)
        maxCountLabel.topAnchor.constraint(equalTo: maxCountRow.topAnchor).isActive = true
        maxCountLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -M.horizontalMargin).isActive = true
        maxCountLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true

        // Wrap Width row
        let wrapWidthRow = makeLabel(text: NSLocalizedString("Wrap Width", comment: "Toast debug wrap width label"), fontSize: 12, weight: .regular, color: .labelColor)
        pin(wrapWidthRow); h(wrapWidthRow, M.rowHeight)
        wrapWidthRow.topAnchor.constraint(equalTo: maxCountRow.bottomAnchor, constant: 10).isActive = true
        wrapWidthRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.horizontalMargin).isActive = true
        wrapWidthRow.widthAnchor.constraint(equalToConstant: M.labelColumnWidth).isActive = true

        wrapWidthField = NSTextField()
        wrapWidthField.stringValue = formattedWrapWidth(ToastStorage.shared.defaultWrapWidth)
        wrapWidthField.alignment = .right
        wrapWidthField.target = self
        wrapWidthField.action = #selector(defaultWrapWidthChanged(_:))
        wrapWidthField.cell?.sendsActionOnEndEditing = true
        pin(wrapWidthField); h(wrapWidthField, M.fieldHeight)
        wrapWidthField.topAnchor.constraint(equalTo: wrapWidthRow.topAnchor).isActive = true
        wrapWidthField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.valueColumnX).isActive = true
        wrapWidthField.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let wrapWidthHintLabel = makeLabel(text: NSLocalizedString("0 = single line", comment: "Toast debug wrap width hint"), fontSize: 11, weight: .regular, color: .secondaryLabelColor)
        pin(wrapWidthHintLabel); h(wrapWidthHintLabel, M.rowHeight)
        wrapWidthHintLabel.topAnchor.constraint(equalTo: wrapWidthRow.topAnchor).isActive = true
        wrapWidthHintLabel.leadingAnchor.constraint(equalTo: wrapWidthField.trailingAnchor, constant: 8).isActive = true
        wrapWidthHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -M.horizontalMargin).isActive = true

        // Position row
        let posLabel = makeLabel(text: NSLocalizedString("Position", comment: "Toast debug position label"), fontSize: 12, weight: .regular, color: .labelColor)
        pin(posLabel); h(posLabel, M.rowHeight)
        posLabel.topAnchor.constraint(equalTo: wrapWidthRow.bottomAnchor, constant: 10).isActive = true
        posLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.horizontalMargin).isActive = true
        posLabel.widthAnchor.constraint(equalToConstant: M.labelColumnWidth).isActive = true

        positionStatusLabel = makeLabel(text: "", fontSize: 11, weight: .medium, color: .secondaryLabelColor)
        pin(positionStatusLabel); h(positionStatusLabel, M.rowHeight)
        positionStatusLabel.topAnchor.constraint(equalTo: posLabel.topAnchor).isActive = true
        positionStatusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.valueColumnX).isActive = true
        positionStatusLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true

        // Reset button
        let resetBtn = NSButton(title: NSLocalizedString("Reset", comment: "Toast debug reset position button"), target: self, action: #selector(resetPosition))
        resetBtn.bezelStyle = .rounded; resetBtn.font = NSFont.systemFont(ofSize: 11)
        pin(resetBtn); h(resetBtn, M.resetButtonHeight)
        resetBtn.topAnchor.constraint(equalTo: posLabel.bottomAnchor, constant: 6).isActive = true
        resetBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.valueColumnX).isActive = true
        resetBtn.widthAnchor.constraint(equalToConstant: 86).isActive = true

        // --- SEND TOAST ---
        let sendHeader = makeLabel(text: NSLocalizedString("SEND TOAST", comment: "Toast debug section header"), fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
        pin(sendHeader); lr(sendHeader); h(sendHeader, 14)
        sendHeader.topAnchor.constraint(equalTo: resetBtn.bottomAnchor, constant: M.sectionSpacing).isActive = true

        // Duration row
        let durLabel = makeLabel(text: NSLocalizedString("Duration", comment: "Toast debug duration label"), fontSize: 12, weight: .regular, color: .labelColor)
        pin(durLabel); h(durLabel, M.rowHeight)
        durLabel.topAnchor.constraint(equalTo: sendHeader.bottomAnchor, constant: 8).isActive = true
        durLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.horizontalMargin).isActive = true
        durLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        durationSlider = NSSlider()
        durationSlider.minValue = 0.5; durationSlider.maxValue = 10.0; durationSlider.doubleValue = 2.5
        durationSlider.target = self; durationSlider.action = #selector(durationChanged)
        pin(durationSlider); h(durationSlider, M.rowHeight)
        durationSlider.topAnchor.constraint(equalTo: durLabel.topAnchor).isActive = true
        durationSlider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.horizontalMargin + 80).isActive = true
        durationSlider.widthAnchor.constraint(equalToConstant: 240).isActive = true

        durationLabel = makeLabel(text: "2.5s", fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        durationLabel.alignment = .right
        pin(durationLabel); h(durationLabel, M.rowHeight)
        durationLabel.topAnchor.constraint(equalTo: durLabel.topAnchor).isActive = true
        durationLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -M.horizontalMargin).isActive = true
        durationLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true

        // Checkboxes
        showsIconCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Show Icon", comment: "Toast debug show icon checkbox"), target: self, action: #selector(showsIconChanged(_:)))
        showsIconCheckbox.font = NSFont.systemFont(ofSize: 12)
        showsIconCheckbox.state = ToastStorage.shared.showsIcon ? .on : .off
        pin(showsIconCheckbox); lr(showsIconCheckbox); h(showsIconCheckbox, M.rowHeight)
        showsIconCheckbox.topAnchor.constraint(equalTo: durLabel.bottomAnchor, constant: 8).isActive = true

        useCustomIconCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Custom Icon (app icon)", comment: "Toast debug custom icon checkbox"), target: nil, action: nil)
        useCustomIconCheckbox.font = NSFont.systemFont(ofSize: 12)
        pin(useCustomIconCheckbox); lr(useCustomIconCheckbox); h(useCustomIconCheckbox, M.rowHeight)
        useCustomIconCheckbox.topAnchor.constraint(equalTo: showsIconCheckbox.bottomAnchor, constant: 8).isActive = true

        showsAccentRibbonCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Ribbon", comment: "Toast debug accent indicator checkbox"), target: self, action: #selector(showsAccentRibbonChanged(_:)))
        showsAccentRibbonCheckbox.font = NSFont.systemFont(ofSize: 12)
        showsAccentRibbonCheckbox.state = ToastStorage.shared.showsAccentIndicator ? .on : .off
        pin(showsAccentRibbonCheckbox); lr(showsAccentRibbonCheckbox); h(showsAccentRibbonCheckbox, M.rowHeight)
        showsAccentRibbonCheckbox.topAnchor.constraint(equalTo: useCustomIconCheckbox.bottomAnchor, constant: 10).isActive = true

        // Message field
        messageField = NSTextField()
        messageField.stringValue = NSLocalizedString("Hello, this is a toast message", comment: "Toast debug default message")
        messageField.placeholderString = NSLocalizedString("Enter toast message...", comment: "Toast debug message placeholder")
        pin(messageField); lr(messageField); h(messageField, M.fieldHeight)
        messageField.topAnchor.constraint(equalTo: showsAccentRibbonCheckbox.bottomAnchor, constant: 14).isActive = true

        // Style buttons (4 columns)
        let styles: [(String, Toast.Style)] = [
            (NSLocalizedString("ℹ️ Info", comment: "Toast debug style button"), .info),
            (NSLocalizedString("✅ Success", comment: "Toast debug style button"), .success),
            (NSLocalizedString("⚠️ Warning", comment: "Toast debug style button"), .warning),
            (NSLocalizedString("❌ Error", comment: "Toast debug style button"), .error),
        ]
        let buttonWidth = (cw - CGFloat(styles.count - 1) * 6) / CGFloat(styles.count)
        styleButtons = []
        var prevStyleBtn: NSButton? = nil
        for (index, (title, _)) in styles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(styleSelected(_:)))
            button.bezelStyle = .rounded; button.font = NSFont.systemFont(ofSize: 11); button.tag = index
            if index == 0 { button.state = .on }
            pin(button); h(button, M.buttonHeight)
            button.topAnchor.constraint(equalTo: messageField.bottomAnchor, constant: 10).isActive = true
            button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
            if let prev = prevStyleBtn {
                button.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: 6).isActive = true
            } else {
                button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: M.horizontalMargin).isActive = true
            }
            styleButtons.append(button)
            prevStyleBtn = button
        }
        let styleRow = styleButtons.first!  // reference for next section

        // --- SCENARIO TESTS ---
        let testHeader = makeLabel(text: NSLocalizedString("SCENARIO TESTS", comment: "Toast debug section header"), fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
        pin(testHeader); lr(testHeader); h(testHeader, 14)
        testHeader.topAnchor.constraint(equalTo: styleRow.bottomAnchor, constant: M.sectionSpacing).isActive = true

        let tests: [(String, String, Selector)] = [
            (NSLocalizedString("🎨 All Styles", comment: ""), NSLocalizedString("Show each style", comment: ""), #selector(testAllStyles)),
            (NSLocalizedString("📚 Stack Test", comment: ""), NSLocalizedString("Fill to max count", comment: ""), #selector(testStackFill)),
            (NSLocalizedString("🔁 Overflow", comment: ""), NSLocalizedString("Exceed max, test eviction", comment: ""), #selector(testOverflow)),
            (NSLocalizedString("🔇 Dedup", comment: ""), NSLocalizedString("Rapid same message", comment: ""), #selector(testDedup)),
            (NSLocalizedString("📏 Long Text", comment: ""), NSLocalizedString("Wrap/truncate preview", comment: "Toast debug quick test subtitle"), #selector(testLongText)),
            (NSLocalizedString("🧹 Dismiss All", comment: ""), NSLocalizedString("Clear all toasts", comment: ""), #selector(testDismissAll)),
        ]
        let gridCols = 2
        let cellWidth = (cw - M.gridColumnSpacing) / CGFloat(gridCols)
        var lastRowButtons: [NSButton] = []
        for (index, (title, subtitle, action)) in tests.enumerated() {
            let col = index % gridCols
            let row = index / gridCols
            let button = NSButton(title: "\(title)\n\(subtitle)", target: self, action: action)
            button.bezelStyle = .rounded; button.font = NSFont.systemFont(ofSize: 11)
            pin(button)
            button.widthAnchor.constraint(equalToConstant: cellWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: M.gridCellHeight).isActive = true
            let xOffset = M.horizontalMargin + CGFloat(col) * (cellWidth + M.gridColumnSpacing)
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: xOffset).isActive = true
            if row == 0 {
                button.topAnchor.constraint(equalTo: testHeader.bottomAnchor, constant: 8).isActive = true
            } else {
                let topOffset: CGFloat = 8 + CGFloat(row) * (M.gridCellHeight + M.gridCellSpacing)
                button.topAnchor.constraint(equalTo: testHeader.bottomAnchor, constant: topOffset).isActive = true
            }
            if row == (tests.count - 1) / gridCols { lastRowButtons.append(button) }
        }

        // Bottom constraint — last row of test buttons + padding = bottom
        if let lastBtn = lastRowButtons.first {
            lastBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -M.bottomPadding).isActive = true
        }
    }

    private func resolvedTopInset(for panel: NSPanel) -> CGFloat {
        let titlebarHeight = panel.frame.height - panel.contentLayoutRect.height
        return max(LayoutMetrics.topPadding, titlebarHeight + 10)
    }

    private func makeLabel(text: String, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        return label
    }

    // MARK: - Actions (Configuration)

    @objc private func maxCountChanged() {
        let value = maxCountSlider.integerValue
        maxCountLabel.stringValue = "\(value)"
        ToastStorage.shared.maxCount = value
        ToastManager.shared.applyMaxCountChange()
    }

    @objc private func defaultWrapWidthChanged(_ sender: NSTextField) {
        let trimmedValue = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedValue = Double(trimmedValue) else {
            applyWrapWidthPreference()
            return
        }

        ToastStorage.shared.defaultWrapWidth = CGFloat(parsedValue)
        applyWrapWidthPreference()
    }

    @objc private func resetPosition() {
        ToastManager.shared.resetToDefaultAnchor()
        refreshPositionStatus()
    }

    // MARK: - Actions (Send Toast)

    @objc private func styleSelected(_ sender: NSButton) {
        let allStyles = Array(Toast.Style.allCases)
        guard sender.tag < allStyles.count else { return }
        selectedStyle = allStyles[sender.tag]
        for (i, btn) in styleButtons.enumerated() {
            btn.state = (i == sender.tag) ? .on : .off
        }
        emitToast(allowDuplicateVisibleMessage: true)
    }

    @objc private func durationChanged() {
        durationLabel.stringValue = String(format: "%.1fs", durationSlider.doubleValue)
    }

    @objc private func showsAccentRibbonChanged(_ sender: NSButton) {
        ToastStorage.shared.showsAccentIndicator = (sender.state == .on)
        applyAccentRibbonPreference()
    }

    @objc private func showsIconChanged(_ sender: NSButton) {
        ToastStorage.shared.showsIcon = (sender.state == .on)
        applyIconPreference()
    }

    @objc private func anchorDidChange() {
        refreshPositionStatus()
    }

    private func emitToast(allowDuplicateVisibleMessage: Bool) {
        let message = messageField.stringValue.isEmpty
            ? NSLocalizedString("Test Toast", comment: "Toast debug fallback message")
            : messageField.stringValue
        let duration = durationSlider.doubleValue
        let showsIcon = ToastStorage.shared.showsIcon
        let icon: NSImage? = useCustomIconCheckbox.state == .on ? NSApp.applicationIconImage : nil
        Toast.show(
            message,
            style: selectedStyle,
            duration: duration,
            icon: icon,
            showsIcon: showsIcon,
            allowDuplicateVisibleMessage: allowDuplicateVisibleMessage
        )
        DispatchQueue.main.async { [weak self] in
            self?.applyAccentRibbonPreference()
            self?.applyIconPreference()
        }
    }

    // MARK: - Actions (Quick Tests)

    @objc private func testAllStyles() {
        let styles: [(String, Toast.Style)] = [
            (NSLocalizedString("Info style", comment: "Toast debug quick test message"), .info),
            (NSLocalizedString("Success style", comment: "Toast debug quick test message"), .success),
            (NSLocalizedString("Warning style", comment: "Toast debug quick test message"), .warning),
            (NSLocalizedString("Error style", comment: "Toast debug quick test message"), .error),
        ]
        for (i, (name, style)) in styles.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                self.showToast(
                    String(format: NSLocalizedString("Style: %@", comment: "Toast debug quick test format"), name),
                    style: style,
                    duration: 3.0
                )
            }
        }
    }

    @objc private func testStackFill() {
        let max = ToastStorage.shared.maxCount
        for i in 0..<max {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                self.showToast(
                    String(format: NSLocalizedString("Toast %d of %d", comment: "Toast debug stack fill format"), i + 1, max),
                    style: .info,
                    duration: 5.0
                )
            }
        }
    }

    @objc private func testOverflow() {
        let max = ToastStorage.shared.maxCount
        let total = max + 2
        for i in 0..<total {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                self.showToast(
                    String(format: NSLocalizedString("Overflow %d of %d", comment: "Toast debug overflow format"), i + 1, total),
                    style: .warning,
                    duration: 8.0
                )
            }
        }
    }

    @objc private func testDedup() {
        for _ in 0..<5 {
            showToast(
                NSLocalizedString("Dedup test - same message", comment: "Toast debug dedup test message"),
                style: .info,
                duration: 2.0
            )
        }
    }

    @objc private func testLongText() {
        showToast(
            NSLocalizedString(
                "This is a very long toast message used to preview wrapping and truncation behavior in the toast notification.",
                comment: "Toast debug long text test message"
            ),
            style: .warning,
            duration: 4.0
        )
    }

    @objc private func testDismissAll() {
        Toast.dismissAll()
    }

    // MARK: - Toast Helpers

    private func showToast(_ message: String, style: Toast.Style, duration: TimeInterval, icon: NSImage? = nil, allowDuplicateVisibleMessage: Bool = false) {
        Toast.show(
            message,
            style: style,
            duration: duration,
            icon: icon,
            showsIcon: ToastStorage.shared.showsIcon,
            allowDuplicateVisibleMessage: allowDuplicateVisibleMessage
        )
        DispatchQueue.main.async { [weak self] in
            self?.applyAccentRibbonPreference()
            self?.applyIconPreference()
        }
    }

    private func applyAccentRibbonPreference() {
        showsAccentRibbonCheckbox?.state = ToastStorage.shared.showsAccentIndicator ? .on : .off
        ToastManager.shared.applyAccentIndicatorVisibilityChange()
    }

    private func applyIconPreference() {
        let showsIcon = ToastStorage.shared.showsIcon
        showsIconCheckbox?.state = showsIcon ? .on : .off
        useCustomIconCheckbox?.isEnabled = showsIcon
        useCustomIconCheckbox?.alphaValue = showsIcon ? 1.0 : 0.5
    }

    private func applyWrapWidthPreference() {
        wrapWidthField?.stringValue = formattedWrapWidth(ToastStorage.shared.defaultWrapWidth)
    }

    private func formattedWrapWidth(_ value: CGFloat) -> String {
        let roundedValue = value.rounded()
        if abs(value - roundedValue) < 0.001 {
            return "\(Int(roundedValue))"
        }
        return String(format: "%.1f", value)
    }

    private func refreshPositionStatus() {
        guard let positionStatusLabel = positionStatusLabel else { return }

        let hasCustomPosition = ToastStorage.shared.hasCustomPosition
        positionStatusLabel.stringValue = hasCustomPosition
            ? NSLocalizedString("Saved", comment: "Toast position saved status")
            : NSLocalizedString("Default", comment: "Toast position default status")
        positionStatusLabel.textColor = hasCustomPosition ? positionStatusActiveColor : .secondaryLabelColor
    }
}
