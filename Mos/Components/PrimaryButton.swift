//
//  PrimaryButton.swift
//  Mos
//  带样式的按钮
//  Created by 陈标 on 2025/9/10.
//  Copyright © 2025 Caldis. All rights reserved.
//

import AppKit

class PrimaryButton: NSControl {

    // 颜色配置 - 根据外观动态切换
    private let cornerRadius: CGFloat = 12.0

    private var backgroundColor: NSColor {
        if #available(macOS 10.14, *) {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                // 深色模式: 暗蓝底 + 透明
                return NSColor(red: 0.08, green: 0.26, blue: 0.52, alpha: 0.75)
            } else {
                // 浅色模式: 标准蓝色 + 透明
                return NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.15)
            }
        } else {
            return NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.15)
        }
    }

    private var borderColor: NSColor {
        if #available(macOS 10.14, *) {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                // 深色模式: 亮蓝边框
                return NSColor(red: 0.36, green: 0.64, blue: 1.0, alpha: 1.0)
            } else {
                // 浅色模式: 标准蓝边框
                return NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.6)
            }
        } else {
            return NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.6)
        }
    }

    private var isHovered: Bool = false
    public var onMouseDown: ((PrimaryButton) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.wantsLayer = true
        self.addTrackingArea(NSTrackingArea(
            rect: self.bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        // 监听外观变化
        if #available(macOS 10.14, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appearanceChanged),
                name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil
            )
        }
    }

    @available(macOS 10.14, *)
    @objc private func appearanceChanged() {
        needsDisplay = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Hover 时增加背景不透明度
        let fillColor: NSColor
        if isHovered {
            if #available(macOS 10.14, *) {
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                if isDark {
                    fillColor = NSColor(red: 0.08, green: 0.26, blue: 0.52, alpha: 0.95)
                } else {
                    fillColor = NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.25)
                }
            } else {
                fillColor = NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.25)
            }
        } else {
            fillColor = backgroundColor
        }

        // 绘制圆角矩形背景
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()

        // 绘制边框
        borderColor.setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onMouseDown?(self)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        needsDisplay = true
    }
}
