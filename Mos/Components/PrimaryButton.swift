//
//  PrimaryButton.swift
//  Mos
//  带样式的按钮
//  Created by 陈标 on 2025/9/10.
//  Copyright © 2025 Caldis. All rights reserved.
//

import AppKit

class PrimaryButton: NSControl {

    private let cornerRadius: CGFloat = 12.0
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

        // 监听外观变化 (兼容 macOS 10.13+)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func appearanceChanged() {
        needsDisplay = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 根据 hover 状态选择背景色
        let fillColor = isHovered
            ? NSColor.getPrimaryButtonBackgroundHovered(for: self)
            : NSColor.getPrimaryButtonBackground(for: self)

        // 绘制圆角矩形背景
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()

        // 绘制边框
        NSColor.getPrimaryButtonBorder(for: self).setStroke()
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
