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

    static let shared = ToastPanel()

    private var window: NSPanel?

    // MARK: - UI Controls (Configuration)
    private var maxCountSlider: NSSlider!
    private var maxCountLabel: NSTextField!
    private var positionStatusLabel: NSTextField!

    // MARK: - UI Controls (Send Toast)
    private var messageField: NSTextField!
    private var styleButtons: [NSButton] = []
    private var selectedStyle: Toast.Style = .info
    private var durationSlider: NSSlider!
    private var durationLabel: NSTextField!
    private var useCustomIconCheckbox: NSButton!

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
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = buildWindow()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build Window

    private func buildWindow() -> NSPanel {
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 546

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
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

        // 毛玻璃背景
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)))
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

        buildContent(in: effectView, width: panelWidth, height: panelHeight)

        return panel
    }

    private func buildContent(in container: NSView, width: CGFloat, height: CGFloat) {
        // 布局采用 "top" 变量追踪下一个控件的顶边位置
        // macOS 坐标系: origin.y 是底边, 控件向上延伸
        // 所以 origin.y = top - controlHeight
        let margin: CGFloat = 20
        let contentWidth = width - margin * 2
        var top = height - 50  // 留出 titlebar 空间

        // --- Header ---
        let titleH: CGFloat = 22
        let titleLabel = makeLabel(text: NSLocalizedString("Toast Debug", comment: "Toast debug panel title"), fontSize: 18, weight: .semibold, color: .white)
        titleLabel.frame = NSRect(x: margin, y: top - titleH, width: contentWidth, height: titleH)
        container.addSubview(titleLabel)
        top -= titleH + 2

        let subtitleH: CGFloat = 16
        let subtitleLabel = makeLabel(text: NSLocalizedString("Component testing & configuration", comment: "Toast debug panel subtitle"), fontSize: 12, weight: .regular, color: .secondaryLabelColor)
        subtitleLabel.frame = NSRect(x: margin, y: top - subtitleH, width: contentWidth, height: subtitleH)
        container.addSubview(subtitleLabel)
        top -= subtitleH + 16

        // === SECTION: Configuration ===
        top = placeSectionHeader(in: container, title: NSLocalizedString("CONFIGURATION", comment: "Toast debug section header"), top: top, margin: margin, width: contentWidth)

        // Max Simultaneous
        let rowH: CGFloat = 18
        let maxCountRow = makeLabel(text: NSLocalizedString("Max Simultaneous", comment: "Toast debug max count label"), fontSize: 12, weight: .regular, color: .labelColor)
        maxCountRow.frame = NSRect(x: margin, y: top - rowH, width: 140, height: rowH)
        container.addSubview(maxCountRow)

        maxCountSlider = NSSlider(frame: NSRect(x: margin + 180, y: top - rowH, width: 150, height: rowH))
        maxCountSlider.minValue = 1
        maxCountSlider.maxValue = 8
        maxCountSlider.integerValue = ToastStorage.shared.maxCount
        maxCountSlider.target = self
        maxCountSlider.action = #selector(maxCountChanged)
        container.addSubview(maxCountSlider)

        maxCountLabel = makeLabel(text: "\(ToastStorage.shared.maxCount)", fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        maxCountLabel.frame = NSRect(x: margin + 340, y: top - rowH, width: 30, height: rowH)
        maxCountLabel.alignment = .right
        container.addSubview(maxCountLabel)
        top -= rowH + 10

        // Position
        let posLabel = makeLabel(text: NSLocalizedString("Position", comment: "Toast debug position label"), fontSize: 12, weight: .regular, color: .labelColor)
        posLabel.frame = NSRect(x: margin, y: top - rowH, width: 140, height: rowH)
        container.addSubview(posLabel)

        positionStatusLabel = makeLabel(
            text: ToastStorage.shared.hasCustomPosition ? NSLocalizedString("Saved", comment: "Toast position saved status") : NSLocalizedString("Default", comment: "Toast position default status"),
            fontSize: 11, weight: .medium,
            color: ToastStorage.shared.hasCustomPosition ? NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0) : .secondaryLabelColor
        )
        positionStatusLabel.frame = NSRect(x: margin + 180, y: top - rowH, width: 60, height: rowH)
        container.addSubview(positionStatusLabel)

        let resetBtnH: CGFloat = 22
        let resetBtn = NSButton(frame: NSRect(x: margin + 260, y: top - resetBtnH, width: 60, height: resetBtnH))
        resetBtn.title = NSLocalizedString("Reset", comment: "Toast debug reset position button")
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 11)
        resetBtn.target = self
        resetBtn.action = #selector(resetPosition)
        container.addSubview(resetBtn)
        top -= resetBtnH + 16

        // === SECTION: Send Toast ===
        top = placeSectionHeader(in: container, title: NSLocalizedString("SEND TOAST", comment: "Toast debug section header"), top: top, margin: margin, width: contentWidth)

        // Message
        let fieldH: CGFloat = 22
        messageField = NSTextField(frame: NSRect(x: margin, y: top - fieldH, width: contentWidth, height: fieldH))
        messageField.stringValue = "Hello, this is a toast message"
        messageField.placeholderString = NSLocalizedString("Enter toast message...", comment: "Toast debug message placeholder")
        container.addSubview(messageField)
        top -= fieldH + 10

        // Style buttons
        let styleBtnH: CGFloat = 24
        let styles: [(String, Toast.Style)] = [
            ("ℹ️ Info", .info), ("✅ Success", .success), ("⚠️ Warning", .warning), ("❌ Error", .error)
        ]
        let btnWidth: CGFloat = (contentWidth - CGFloat(styles.count - 1) * 6) / CGFloat(styles.count)
        styleButtons = []
        for (i, (title, _)) in styles.enumerated() {
            let btn = NSButton(frame: NSRect(x: margin + CGFloat(i) * (btnWidth + 6), y: top - styleBtnH, width: btnWidth, height: styleBtnH))
            btn.title = title
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.tag = i
            btn.target = self
            btn.action = #selector(styleSelected(_:))
            if i == 0 { btn.state = .on }
            container.addSubview(btn)
            styleButtons.append(btn)
        }
        top -= styleBtnH + 10

        // Duration
        let durLabel = makeLabel(text: NSLocalizedString("Duration", comment: "Toast debug duration label"), fontSize: 12, weight: .regular, color: .labelColor)
        durLabel.frame = NSRect(x: margin, y: top - rowH, width: 60, height: rowH)
        container.addSubview(durLabel)

        durationSlider = NSSlider(frame: NSRect(x: margin + 80, y: top - rowH, width: 240, height: rowH))
        durationSlider.minValue = 0.5
        durationSlider.maxValue = 10.0
        durationSlider.doubleValue = 2.5
        durationSlider.target = self
        durationSlider.action = #selector(durationChanged)
        container.addSubview(durationSlider)

        durationLabel = makeLabel(text: "2.5s", fontSize: 12, weight: .medium, color: .secondaryLabelColor)
        durationLabel.frame = NSRect(x: margin + 330, y: top - rowH, width: 50, height: rowH)
        durationLabel.alignment = .right
        container.addSubview(durationLabel)
        top -= rowH + 8

        // Custom Icon
        useCustomIconCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Custom Icon (app icon)", comment: "Toast debug custom icon checkbox"), target: nil, action: nil)
        useCustomIconCheckbox.frame = NSRect(x: margin, y: top - rowH, width: contentWidth, height: rowH)
        useCustomIconCheckbox.font = NSFont.systemFont(ofSize: 12)
        container.addSubview(useCustomIconCheckbox)
        top -= rowH + 10

        // Show Toast button
        let fireBtnH: CGFloat = 30
        let fireButton = NSButton(frame: NSRect(x: margin, y: top - fireBtnH, width: contentWidth, height: fireBtnH))
        fireButton.title = NSLocalizedString("Show Toast", comment: "Toast debug show toast button")
        fireButton.bezelStyle = .rounded
        fireButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        fireButton.target = self
        fireButton.action = #selector(fireToast)
        container.addSubview(fireButton)
        top -= fireBtnH + 16

        // === SECTION: Quick Tests ===
        top = placeSectionHeader(in: container, title: NSLocalizedString("QUICK TESTS", comment: "Toast debug section header"), top: top, margin: margin, width: contentWidth)

        let tests: [(String, String, Selector)] = [
            ("🎨 All Styles", "Show each style", #selector(testAllStyles)),
            ("📚 Stack Test", "Fill to max count", #selector(testStackFill)),
            ("🔁 Overflow", "Exceed max, test eviction", #selector(testOverflow)),
            ("🔇 Dedup", "Rapid same message", #selector(testDedup)),
            ("📏 Long Text", "Truncation test", #selector(testLongText)),
            ("🧹 Dismiss All", "Clear all toasts", #selector(testDismissAll)),
        ]
        let gridCols = 2
        let cellWidth = (contentWidth - 8) / CGFloat(gridCols)
        let cellHeight: CGFloat = 36
        let cellSpacing: CGFloat = 6
        for (i, (title, subtitle, action)) in tests.enumerated() {
            let col = i % gridCols
            let row = i / gridCols
            let cellX = margin + CGFloat(col) * (cellWidth + 8)
            let cellY = top - CGFloat(row + 1) * cellHeight - CGFloat(row) * cellSpacing

            let btn = NSButton(frame: NSRect(x: cellX, y: cellY, width: cellWidth, height: cellHeight))
            btn.title = "\(title)\n\(subtitle)"
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.target = self
            btn.action = action
            container.addSubview(btn)
        }
    }

    // MARK: - Layout Helpers

    private func placeSectionHeader(in parent: NSView, title: String, top: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        let headerH: CGFloat = 14
        let label = makeLabel(text: title, fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
        label.frame = NSRect(x: margin, y: top - headerH, width: width, height: headerH)
        parent.addSubview(label)
        return top - headerH - 8
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

    @objc private func resetPosition() {
        ToastStorage.shared.resetPosition()
        positionStatusLabel.stringValue = NSLocalizedString("Default", comment: "Toast position default status")
        positionStatusLabel.textColor = .secondaryLabelColor
    }

    // MARK: - Actions (Send Toast)

    @objc private func styleSelected(_ sender: NSButton) {
        let allStyles = Array(Toast.Style.allCases)
        guard sender.tag < allStyles.count else { return }
        selectedStyle = allStyles[sender.tag]
        for (i, btn) in styleButtons.enumerated() {
            btn.state = (i == sender.tag) ? .on : .off
        }
    }

    @objc private func durationChanged() {
        durationLabel.stringValue = String(format: "%.1fs", durationSlider.doubleValue)
    }

    @objc private func fireToast() {
        let message = messageField.stringValue.isEmpty ? "Test Toast" : messageField.stringValue
        let duration = durationSlider.doubleValue
        let icon: NSImage? = useCustomIconCheckbox.state == .on ? NSApp.applicationIconImage : nil
        Toast.show(message, style: selectedStyle, duration: duration, icon: icon)
    }

    // MARK: - Actions (Quick Tests)

    @objc private func testAllStyles() {
        let styles: [(String, Toast.Style)] = [
            ("Info style", .info), ("Success style", .success),
            ("Warning style", .warning), ("Error style", .error)
        ]
        for (i, (name, style)) in styles.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                Toast.show("Style: \(name)", style: style, duration: 3.0)
            }
        }
    }

    @objc private func testStackFill() {
        let max = ToastStorage.shared.maxCount
        for i in 0..<max {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                Toast.show("Toast \(i + 1) of \(max)", style: .info, duration: 5.0)
            }
        }
    }

    @objc private func testOverflow() {
        let max = ToastStorage.shared.maxCount
        let total = max + 2
        for i in 0..<total {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                Toast.show("Overflow \(i + 1) of \(total)", style: .warning, duration: 8.0)
            }
        }
    }

    @objc private func testDedup() {
        for _ in 0..<5 {
            Toast.show("Dedup test - same message", style: .info, duration: 2.0)
        }
    }

    @objc private func testLongText() {
        Toast.show("This is a very long toast message that should be truncated after two lines because nobody wants to read a novel in a toast notification, right? Let's see how this handles.", style: .warning, duration: 4.0)
    }

    @objc private func testDismissAll() {
        Toast.dismissAll()
    }
}
