//
//  BrandTag.swift
//  Mos
//  统一的品牌标签渲染工具 - 支持多厂商品牌标识
//  Created by Mos on 2026/3/19.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

/// 可复用标签配置
struct BrandTagConfig: Equatable {
    let name: String           // 标签文字 (如 "Logi")
    let bgColor: NSColor       // 背景色
    let textColor: NSColor     // 文字色
    let borderColor: NSColor?  // 可选描边色, 用于提升浅色背景上的边界感
    let innerHighlightColor: NSColor? // 可选内高光, 比外描边更克制
    let gradientColors: [NSColor]? // 可选渐变色, nil 时使用纯色背景

    init(
        name: String,
        bgColor: NSColor,
        textColor: NSColor,
        borderColor: NSColor? = nil,
        innerHighlightColor: NSColor? = nil,
        gradientColors: [NSColor]? = nil
    ) {
        self.name = name
        self.bgColor = bgColor
        self.textColor = textColor
        self.borderColor = borderColor
        self.innerHighlightColor = innerHighlightColor
        self.gradientColors = gradientColors
    }

    // MARK: - 内置标签

    /// Logitech: 绿底黑字
    static let logi = BrandTagConfig(
        name: "Logi",
        bgColor: NSColor(calibratedRed: 0.0, green: 0.992, blue: 0.812, alpha: 1.0),  // #00FDCF
        textColor: NSColor(calibratedWhite: 0.15, alpha: 1.0)
    )

    /// Mos: 深色蓝紫渐变, 呼应应用图标的霓虹光环主题
    static let mos = BrandTagConfig(
        name: "Mos",
        bgColor: NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.16, alpha: 1.0),  // #0D1229
        textColor: NSColor(calibratedRed: 0.92, green: 0.98, blue: 1.0, alpha: 1.0), // #EBFAFF
        innerHighlightColor: NSColor(calibratedRed: 0.86, green: 0.94, blue: 1.0, alpha: 0.18),
        gradientColors: [
            NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.36, alpha: 1.0), // #0F1A5C
            NSColor(calibratedRed: 0.50, green: 0.22, blue: 0.85, alpha: 1.0), // #8038D9
        ]
    )
}

private final class BrandTagBackgroundView: NSView {
    private let brand: BrandTagConfig
    private let cornerRadius: CGFloat

    init(brand: BrandTagConfig, cornerRadius: CGFloat) {
        self.brand = brand
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        BrandTag.drawTagBackground(brand: brand, in: bounds, clippingTo: bgPath)
        BrandTag.drawTagStrokeIfNeeded(brand: brand, path: bgPath)
        BrandTag.drawTagInnerHighlightIfNeeded(brand: brand, in: bounds, cornerRadius: cornerRadius)
    }
}

/// 标签渲染工具
struct BrandTag {

    // MARK: - 判断

    /// 按键码是否属于某个品牌
    static func isLogiCode(_ code: UInt16) -> Bool {
        return LogiCenter.shared.isLogiCode(code)
    }

    /// 快捷键 ID 是否属于某个品牌
    static func isLogiAction(_ identifier: String) -> Bool {
        return identifier.hasPrefix("logi")
    }

    /// 快捷键 ID 是否属于 Mos 标签动作
    static func isMosAction(_ identifier: String) -> Bool {
        return identifier.hasPrefix("mos")
    }

    /// 获取按键码对应的标签配置 (nil = 非标签按键)
    static func tagForCode(_ code: UInt16) -> BrandTagConfig? {
        if isLogiCode(code) { return .logi }
        return nil
    }

    /// 获取快捷键 ID 对应的标签配置 (nil = 非标签动作)
    static func tagForAction(_ identifier: String) -> BrandTagConfig? {
        if isLogiAction(identifier) { return .logi }
        if isMosAction(identifier) { return .mos }
        return nil
    }

    /// 获取按键码对应的品牌配置 (兼容旧调用, nil = 非品牌/标签按键)
    static func brandForCode(_ code: UInt16) -> BrandTagConfig? {
        return tagForCode(code)
    }

    /// 获取快捷键 ID 对应的品牌配置 (兼容旧调用, nil = 非品牌/标签动作)
    static func brandForAction(_ identifier: String) -> BrandTagConfig? {
        return tagForAction(identifier)
    }

    // MARK: - 标签文字 (用于 NSButton.title 等纯文本场景)

    /// 在名称前添加品牌前缀 (纯文本 fallback)
    static func prefixedName(_ name: String, brand: BrandTagConfig) -> String {
        return "[\(brand.name)] \(name)"
    }

    /// 创建带品牌 tag 的 NSAttributedString (用于 NSButton.attributedTitle)
    /// 渲染为: [彩色tag] + 空格 + 按键名
    static func attributedTitle(_ name: String, brand: BrandTagConfig, fontSize: CGFloat = 12) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Tag 部分: 品牌名 + 圆角背景
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize - 4, weight: .bold),
            .foregroundColor: brand.textColor,
            .backgroundColor: brand.bgColor,
        ]
        // 用空格包裹让背景色有 padding 效果
        result.append(NSAttributedString(string: " \(brand.name) ", attributes: tagAttrs))

        // 间距
        result.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: fontSize - 4)]))

        // 按键名部分
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        result.append(NSAttributedString(string: name, attributes: nameAttrs))

        return result
    }

    // MARK: - 标签 NSView (用于 KeyPreview 等自定义 View 场景)

    /// 创建独立的品牌标签 View
    static func createTagView(brand: BrandTagConfig, fontSize: CGFloat = 7, height: CGFloat = 12) -> NSView {
        let container = BrandTagBackgroundView(brand: brand, cornerRadius: 2.5)
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: brand.name)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        label.textColor = brand.textColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -0.5),
            container.widthAnchor.constraint(equalTo: label.widthAnchor, constant: 5),
            container.heightAnchor.constraint(equalToConstant: height),
        ])

        return container
    }

    // MARK: - 标签 NSImage (用于 NSMenuItem / NSButton / NSPopUpButton 场景)

    /// 创建品牌标签图片
    static func createTagImage(brand: BrandTagConfig, fontSize: CGFloat = 7, height: CGFloat = 12, padH: CGFloat = 4, marginRight: CGFloat = 2) -> NSImage {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: brand.textColor]
        let textSize = (brand.name as NSString).size(withAttributes: attrs)
        let tagWidth = textSize.width + padH * 2
        let imageSize = NSSize(width: tagWidth + marginRight, height: height)

        let image = NSImage(size: imageSize)
        image.lockFocus()
        let bgRect = NSRect(x: 0, y: 0, width: tagWidth, height: height)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3)
        drawTagBackground(brand: brand, in: bgRect, clippingTo: bgPath)
        drawTagStrokeIfNeeded(brand: brand, path: bgPath)
        drawTagInnerHighlightIfNeeded(brand: brand, in: bgRect, cornerRadius: 3)
        let textRect = NSRect(x: padH, y: (height - textSize.height) / 2, width: textSize.width, height: textSize.height)
        (brand.name as NSString).draw(in: textRect, withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    fileprivate static func drawTagBackground(brand: BrandTagConfig, in rect: NSRect, clippingTo path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let gradientColors = brand.gradientColors,
           let gradient = NSGradient(colors: gradientColors) {
            gradient.draw(in: rect, angle: 0)
        } else {
            brand.bgColor.setFill()
            rect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    fileprivate static func drawTagStrokeIfNeeded(brand: BrandTagConfig, path: NSBezierPath) {
        guard let borderColor = brand.borderColor else { return }
        borderColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    fileprivate static func drawTagInnerHighlightIfNeeded(brand: BrandTagConfig, in rect: NSRect, cornerRadius: CGFloat) {
        guard let innerHighlightColor = brand.innerHighlightColor else { return }
        let highlightRect = rect.insetBy(dx: 0.75, dy: 0.75)
        let highlightRadius = max(0, cornerRadius - 0.75)
        let highlightPath = NSBezierPath(
            roundedRect: highlightRect,
            xRadius: highlightRadius,
            yRadius: highlightRadius
        )
        innerHighlightColor.setStroke()
        highlightPath.lineWidth = 1
        highlightPath.stroke()
    }

    /// 创建 [品牌标签] + [原图标] 的组合图片
    static func createPrefixedImage(brand: BrandTagConfig, original: NSImage?, fontSize: CGFloat = 7, tagHeight: CGFloat = 12, gap: CGFloat = 5) -> NSImage {
        let tagImage = createTagImage(brand: brand, fontSize: fontSize, height: tagHeight)
        let tagSize = tagImage.size
        let iconSize = original?.size ?? .zero
        let totalHeight = max(tagSize.height, iconSize.height)
        let totalWidth = tagSize.width + (original != nil ? gap + iconSize.width : 0) + 2

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()
        // Tag
        tagImage.draw(in: NSRect(x: 0, y: (totalHeight - tagSize.height) / 2, width: tagSize.width, height: tagSize.height),
                      from: .zero, operation: .sourceOver, fraction: 1.0)
        // Original icon
        if let icon = original {
            let iconRect = NSRect(x: tagSize.width + gap, y: (totalHeight - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            // 模板图标在 lockFocus 上下文中默认渲染为黑色,
            // 用 labelColor + sourceAtop 着色, 使其在暗色模式下自动变为白色
            if icon.isTemplate {
                NSColor.labelColor.setFill()
                iconRect.fill(using: .sourceAtop)
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
