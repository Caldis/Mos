//
//  GlowDebugPanel.swift
//  Mos
//  光晕效果工作台: 左侧效果库列表 + 右侧内嵌实时预览 + 下方分区参数控件
//  入口: 状态栏图标 Option 菜单 → Debug: Glow
//  Created by Caldis on 2026/7/17. Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import MetalKit

class GlowDebugPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    static let shared = GlowDebugPanel()

    // MARK: - 共享参数行定义 (keyPath 驱动)

    private struct SharedRow {
        let title: String
        let min: Double
        let max: Double
        let format: String
        let keyPath: WritableKeyPath<GlowParams, Float>
    }
    // 分区: 全局 / 布局 / 调色 / 光形
    private let sectionTitles = ["全局", "布局", "调色", "光形"]
    private let sections: [[SharedRow]] = [
        [
            SharedRow(title: "亮度", min: 0.2, max: 3.0, format: "%.2f", keyPath: \.intensity),
            SharedRow(title: "速度", min: 0.0, max: 3.0, format: "%.2f", keyPath: \.speed),
        ],
        [
            SharedRow(title: "外扩", min: 60, max: 300, format: "%.0f", keyPath: \.margin),
            SharedRow(title: "圆角", min: 0, max: 40, format: "%.0f", keyPath: \.cornerRadius),
        ],
        [
            SharedRow(title: "色相", min: 0, max: 1, format: "%.2f", keyPath: \.hueOffset),
            SharedRow(title: "饱和", min: 0.2, max: 1.6, format: "%.2f", keyPath: \.satScale),
            SharedRow(title: "明度", min: 0.5, max: 1.5, format: "%.2f", keyPath: \.baseScale),
        ],
        [
            SharedRow(title: "衰减", min: 0.1, max: 0.6, format: "%.2f", keyPath: \.falloffScale),
            SharedRow(title: "亮线", min: 0, max: 1.5, format: "%.2f", keyPath: \.rimStrength),
        ],
    ]
    private var flatRows: [SharedRow] { sections.flatMap { $0 } }

    // MARK: - 控件引用

    private var window: NSPanel?
    private var previewView: GlowMetalView?
    private var effectTable: NSTableView?
    private var palettePopup: NSPopUpButton?
    private var sharedSliders = [NSSlider]()
    private var sharedValueLabels = [NSTextField]()
    private var slotsGrid: NSStackView?
    private var slotSliders = [NSSlider]()
    private var slotValueLabels = [NSTextField]()
    private var pauseButton: NSButton?

    // MARK: - Show

    func show() {
        if window == nil {
            window = buildWindow()
        }
        refreshAllControls()
        previewView?.isPaused = false
        pauseButton?.title = "暂停预览"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build

    private func buildWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 660),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Glow Studio"
        panel.titlebarAppearsTransparent = true
        panel.minSize = NSSize(width: 820, height: 620)
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .vibrantDark)

        let effectView = NSVisualEffectView()
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
        } else {
            effectView.material = .dark
        }
        panel.contentView = effectView

        // ---- 顶区: 效果列表 + 预览 ----
        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 26
        table.allowsEmptySelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("effect"))
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        effectTable = table
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.drawsBackground = false
        tableScroll.widthAnchor.constraint(equalToConstant: 176).isActive = true

        let preview = GlowPreviewContainer()
        previewView = preview.metalView

        let topRow = NSStackView(views: [tableScroll, preview])
        topRow.orientation = .horizontal
        topRow.spacing = 12
        topRow.distribution = .fill
        topRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        // ---- 分区参数 ----
        var rowIndex = 0
        var groupViews = [NSView]()
        for (sectionIndex, rows) in sections.enumerated() {
            let group = NSStackView()
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = 5
            group.addArrangedSubview(sectionHeader(sectionTitles[sectionIndex]))
            // 调色分区首行插入调色板下拉
            if sectionIndex == 2 {
                let popup = NSPopUpButton()
                popup.addItems(withTitles: GlowEffectCatalog.palettes.map { $0.name })
                popup.target = self
                popup.action = #selector(paletteChanged(_:))
                popup.controlSize = .small
                palettePopup = popup
                let label = smallLabel("调色板", width: 52)
                let popupRow = NSStackView(views: [label, popup])
                popupRow.orientation = .horizontal
                popupRow.spacing = 6
                group.addArrangedSubview(popupRow)
            }
            for row in rows {
                let (view, slider, value) = sliderRow(
                    title: row.title, min: row.min, max: row.max, isInteger: false,
                    tag: rowIndex, action: #selector(sharedSliderChanged(_:)),
                    titleWidth: 52, sliderWidth: 96
                )
                sharedSliders.append(slider)
                sharedValueLabels.append(value)
                group.addArrangedSubview(view)
                rowIndex += 1
            }
            groupViews.append(group)
        }
        let groupsRow = NSStackView(views: groupViews)
        groupsRow.orientation = .horizontal
        groupsRow.alignment = .top
        groupsRow.spacing = 20
        groupsRow.distribution = .fillEqually

        // ---- 效果私有参数 (随所选效果动态重建) ----
        let slotsSection = NSStackView()
        slotsSection.orientation = .vertical
        slotsSection.alignment = .leading
        slotsSection.spacing = 5
        slotsSection.addArrangedSubview(sectionHeader("效果参数"))
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 5
        slotsGrid = grid
        slotsSection.addArrangedSubview(grid)

        // ---- 操作行 ----
        let pause = NSButton(title: "暂停预览", target: self, action: #selector(pauseClick))
        pauseButton = pause
        let buttonRow = NSStackView(views: [
            NSButton(title: "应用到引导窗口", target: self, action: #selector(introClick)),
            pause,
            NSButton(title: "重置当前效果", target: self, action: #selector(resetClick)),
            NSButton(title: "复制参数", target: self, action: #selector(copyClick)),
        ])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        // ---- 根布局 ----
        let root = NSStackView(views: [topRow, groupsRow, slotsSection, buttonRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 36),
            root.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(lessThanOrEqualTo: effectView.bottomAnchor, constant: -14),
            topRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            groupsRow.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])

        // 关闭时暂停预览渲染
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.previewView?.isPaused = true
        }

        rebuildSlotRows()
        table.selectRowIndexes(IndexSet(integer: GlowParams.shared.effectId), byExtendingSelection: false)
        return panel
    }

    // MARK: - 控件工厂

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func smallLabel(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func sliderRow(
        title: String, min: Double, max: Double, isInteger: Bool,
        tag: Int, action: Selector, titleWidth: CGFloat, sliderWidth: CGFloat
    ) -> (NSView, NSSlider, NSTextField) {
        let label = smallLabel(title, width: titleWidth)
        let slider = NSSlider(value: min, minValue: min, maxValue: max, target: self, action: action)
        slider.tag = tag
        slider.isContinuous = true
        slider.controlSize = .small
        if isInteger {
            // 整数参数: 刻度吸附
            slider.numberOfTickMarks = Int(max - min) + 1
            slider.allowsTickMarkValuesOnly = true
        }
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: sliderWidth).isActive = true
        let value = NSTextField(labelWithString: "")
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let row = NSStackView(views: [label, slider, value])
        row.orientation = .horizontal
        row.spacing = 6
        return (row, slider, value)
    }

    // MARK: - 刷新

    private func refreshAllControls() {
        for (index, row) in flatRows.enumerated() where index < sharedSliders.count {
            let current = Double(GlowParams.shared[keyPath: row.keyPath])
            sharedSliders[index].doubleValue = current
            sharedValueLabels[index].stringValue = String(format: row.format, current)
        }
        palettePopup?.selectItem(at: GlowParams.shared.paletteId)
        refreshSlotControls()
    }

    private func refreshSlotControls() {
        let spec = GlowEffectCatalog.all[GlowParams.shared.effectId]
        for (index, slot) in spec.slots.enumerated() where index < slotSliders.count {
            let current = Double(GlowParams.shared.slots[index])
            slotSliders[index].doubleValue = current
            slotValueLabels[index].stringValue = String(format: slot.isInteger ? "%.0f" : "%.2f", current)
        }
    }

    // 按当前效果的 slot 元数据重建私有参数区 (两列网格)
    private func rebuildSlotRows() {
        guard let grid = slotsGrid else { return }
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        slotSliders.removeAll()
        slotValueLabels.removeAll()
        let spec = GlowEffectCatalog.all[GlowParams.shared.effectId]
        var currentRow: NSStackView?
        for (index, slot) in spec.slots.enumerated() {
            let (view, slider, value) = sliderRow(
                title: slot.name, min: Double(slot.min), max: Double(slot.max),
                isInteger: slot.isInteger,
                tag: index, action: #selector(slotSliderChanged(_:)),
                titleWidth: 68, sliderWidth: 220
            )
            slotSliders.append(slider)
            slotValueLabels.append(value)
            if index % 2 == 0 {
                let row = NSStackView(views: [view])
                row.orientation = .horizontal
                row.spacing = 24
                grid.addArrangedSubview(row)
                currentRow = row
            } else {
                currentRow?.addArrangedSubview(view)
            }
        }
        refreshSlotControls()
    }

    // MARK: - 效果列表 (NSTableViewDataSource / Delegate)

    func numberOfRows(in tableView: NSTableView) -> Int {
        return GlowEffectCatalog.all.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("effectCell")
        let label: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            label = reused
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.font = NSFont.systemFont(ofSize: 12)
        }
        label.stringValue = String(format: "%02d  %@", row, GlowEffectCatalog.all[row].name)
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = effectTable, table.selectedRow >= 0,
              table.selectedRow != GlowParams.shared.effectId else { return }
        applyPreset(table.selectedRow)
    }

    // 应用效果预设 (保留布局参数: 外扩与圆角是场景相关的, 不随预设跳变)
    private func applyPreset(_ index: Int) {
        var preset = GlowEffectCatalog.all[index].preset
        preset.margin = GlowParams.shared.margin
        preset.cornerRadius = GlowParams.shared.cornerRadius
        GlowParams.shared = preset
        rebuildSlotRows()
        refreshAllControls()
    }

    // MARK: - Actions

    @objc private func sharedSliderChanged(_ sender: NSSlider) {
        let row = flatRows[sender.tag]
        GlowParams.shared[keyPath: row.keyPath] = Float(sender.doubleValue)
        sharedValueLabels[sender.tag].stringValue = String(format: row.format, sender.doubleValue)
    }

    @objc private func slotSliderChanged(_ sender: NSSlider) {
        let spec = GlowEffectCatalog.all[GlowParams.shared.effectId]
        guard sender.tag < spec.slots.count else { return }
        GlowParams.shared.slots[sender.tag] = Float(sender.doubleValue)
        slotValueLabels[sender.tag].stringValue = String(
            format: spec.slots[sender.tag].isInteger ? "%.0f" : "%.2f", sender.doubleValue
        )
    }

    @objc private func paletteChanged(_ sender: NSPopUpButton) {
        GlowParams.shared.paletteId = sender.indexOfSelectedItem
    }

    @objc private func introClick() {
        // 在真实的引导窗口上查看效果 (同 PreferencesAboutViewController.welcomeWindowButtonClick)
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
        if let windowController = WindowManager.shared.refs[WINDOW_IDENTIFIER.introductionWindowController] as? IntroductionWindowController,
           let viewController = windowController.contentViewController as? IntroductionViewController {
            viewController.setManuallyOpened(true)
        }
        // 面板保持置前方便调参
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func pauseClick() {
        guard let preview = previewView else { return }
        preview.isPaused = !preview.isPaused
        pauseButton?.title = preview.isPaused ? "恢复预览" : "暂停预览"
    }

    @objc private func resetClick() {
        applyPreset(GlowParams.shared.effectId)
    }

    @objc private func copyClick() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GlowParams.shared.swiftLiteral, forType: .string)
        Toast.show("已复制参数代码", style: .success)
    }

}

// MARK: - 预览容器: Metal 渲染 + 居中的虚拟窗口卡片

private final class GlowPreviewContainer: NSView {

    private(set) var metalView: GlowMetalView?
    private let card = NSView()
    private let fallbackLabel = NSTextField(labelWithString: "此设备不支持 Metal, 无法预览")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.055, blue: 0.075, alpha: 1).cgColor
        // Metal 预览 (与实际光晕同一 shader, preview 模式合成到不透明深底)
        if let device = MTLCreateSystemDefaultDevice(),
           let metal = GlowMetalView(device: device, isPreview: true) {
            metalView = metal
            metal.autoresizingMask = [.width, .height]
            addSubview(metal)
        } else {
            fallbackLabel.textColor = .secondaryLabelColor
            addSubview(fallbackLabel)
        }
        // 虚拟窗口卡片 (对应 shader 预览模式中的内缩矩形)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 0.92).cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        let title = NSTextField(labelWithString: "Mos")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(title)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        addSubview(card)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        metalView?.frame = bounds
        // 与 GlowMetalView 预览模式的内缩公式保持一致
        let inset = min(bounds.width, bounds.height) * 0.3
        card.frame = bounds.insetBy(dx: inset, dy: inset)
        fallbackLabel.sizeToFit()
        fallbackLabel.frame.origin = NSPoint(
            x: (bounds.width - fallbackLabel.frame.width) / 2,
            y: (bounds.height - fallbackLabel.frame.height) / 2
        )
    }

}
