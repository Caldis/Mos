//
//  PrimaryButton.swift
//  Mos
//  带样式的按钮
//  Created by 陈标 on 2025/9/10.
//  Copyright © 2025 Caldis. All rights reserved.
//

import AppKit


class PrimaryButton: NSBox {
    
    private var originalFillColor: NSColor?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        originalFillColor = self.fillColor
        setupHover()
    }
    
    // MARK: - Hover 效果处理
    private func setupHover() {
        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard let originalColor = originalFillColor else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().fillColor = adjustBrightness(of: originalColor, factor: 1.2)
        })
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard let originalColor = originalFillColor else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().fillColor = originalColor
        })
    }
    
    private func adjustBrightness(of color: NSColor, factor: CGFloat) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: saturation, brightness: brightness * factor, alpha: alpha)
    }
}
