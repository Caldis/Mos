//
//  GlowDebugPanel.swift
//  Mos
//  光晕效果调试控制台: 实时操控 GlowParams 的全部参数 (入口: 状态栏图标 Option 菜单 → Debug: Glow)
//  Created by Caldis on 2026/7/17. Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

class GlowDebugPanel: NSObject {

    static let shared = GlowDebugPanel()

    // 参数行定义
    private struct Row {
        let title: String
        let min: Double
        let max: Double
        let format: String
        let keyPath: WritableKeyPath<GlowParams, Float>
    }
    private let rows: [Row] = [
        Row(title: "整体亮度", min: 0.2, max: 3.0, format: "%.2f", keyPath: \.intensity),
        Row(title: "外扩范围", min: 60, max: 300, format: "%.0f", keyPath: \.margin),
        Row(title: "窗口圆角", min: 0, max: 40, format: "%.0f", keyPath: \.cornerRadius),
        Row(title: "色相转速", min: 0, max: 0.5, format: "%.2f", keyPath: \.hueSpeed),
        Row(title: "色相偏移", min: 0, max: 1, format: "%.2f", keyPath: \.palettePhase),
        Row(title: "饱和度", min: 0.1, max: 0.6, format: "%.2f", keyPath: \.saturation),
        Row(title: "基础亮度", min: 0.3, max: 0.7, format: "%.2f", keyPath: \.paletteBase),
        Row(title: "波瓣数量", min: 0, max: 8, format: "%.0f", keyPath: \.bandCount),
        Row(title: "波动速度", min: 0, max: 4, format: "%.2f", keyPath: \.bandSpeed),
        Row(title: "波动对比", min: 0, max: 0.6, format: "%.2f", keyPath: \.bandContrast),
        Row(title: "衰减长度", min: 0.1, max: 0.6, format: "%.2f", keyPath: \.falloffScale),
        Row(title: "贴边亮线", min: 0, max: 1.5, format: "%.2f", keyPath: \.rimStrength),
    ]

    private var window: NSPanel?
    private var sliders = [NSSlider]()
    private var valueLabels = [NSTextField]()
    private var pauseButton: NSButton?

    // MARK: - Show

    func show() {
        if window == nil {
            window = buildWindow()
        }
        refreshControls()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build

    private func buildWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 0),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Glow Debug"
        panel.titlebarAppearsTransparent = true
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

        // 参数滑杆行
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(buildRow(index: index, row: row))
        }
        // 操作按钮行
        let pause = NSButton(title: "暂停动画", target: self, action: #selector(pauseClick))
        pauseButton = pause
        let buttonRow = NSStackView(views: [
            NSButton(title: "打开引导窗口", target: self, action: #selector(introClick)),
            pause,
            NSButton(title: "重置", target: self, action: #selector(resetClick)),
            NSButton(title: "复制参数", target: self, action: #selector(copyClick)),
        ])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        stack.addArrangedSubview(buttonRow)

        effectView.addSubview(stack)
        let titlebarHeight: CGFloat = 28
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: titlebarHeight + 8),
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -14),
        ])
        panel.setContentSize(NSSize(width: 380, height: titlebarHeight + 8 + CGFloat(rows.count) * 28 + 44))
        return panel
    }

    private func buildRow(index: Int, row: Row) -> NSView {
        let title = NSTextField(labelWithString: row.title)
        title.font = NSFont.systemFont(ofSize: 12)
        title.widthAnchor.constraint(equalToConstant: 68).isActive = true

        let slider = NSSlider(
            value: Double(GlowParams.shared[keyPath: row.keyPath]),
            minValue: row.min,
            maxValue: row.max,
            target: self,
            action: #selector(sliderChanged(_:))
        )
        slider.tag = index
        slider.isContinuous = true
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        sliders.append(slider)

        let value = NSTextField(labelWithString: "")
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 44).isActive = true
        valueLabels.append(value)

        let rowStack = NSStackView(views: [title, slider, value])
        rowStack.orientation = .horizontal
        rowStack.spacing = 8
        return rowStack
    }

    // MARK: - Refresh

    private func refreshControls() {
        for (index, row) in rows.enumerated() where index < sliders.count {
            let current = Double(GlowParams.shared[keyPath: row.keyPath])
            sliders[index].doubleValue = current
            valueLabels[index].stringValue = String(format: row.format, current)
        }
        pauseButton?.title = (GlowWindowController.active?.isPaused ?? false) ? "恢复动画" : "暂停动画"
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) {
        let row = rows[sender.tag]
        GlowParams.shared[keyPath: row.keyPath] = Float(sender.doubleValue)
        valueLabels[sender.tag].stringValue = String(format: row.format, sender.doubleValue)
    }

    @objc private func introClick() {
        // 手动打开引导窗口 (同 PreferencesAboutViewController.welcomeWindowButtonClick)
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
        if let windowController = WindowManager.shared.refs[WINDOW_IDENTIFIER.introductionWindowController] as? IntroductionWindowController,
           let viewController = windowController.contentViewController as? IntroductionViewController {
            viewController.setManuallyOpened(true)
        }
        // 面板保持置前方便调参
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func pauseClick() {
        guard let active = GlowWindowController.active else { return }
        active.isPaused = !active.isPaused
        refreshControls()
    }

    @objc private func resetClick() {
        GlowParams.shared = GlowParams.defaults
        refreshControls()
    }

    @objc private func copyClick() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GlowParams.shared.swiftLiteral, forType: .string)
        Toast.show("已复制参数代码", style: .success)
    }

}
