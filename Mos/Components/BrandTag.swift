//
//  BrandTag.swift
//  Mos
//  统一的品牌标签渲染工具 - 支持多厂商品牌标识
//  Created by Mos on 2026/3/19.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

/// 品牌标签配置
struct BrandTagConfig {
    let name: String           // 标签文字 (如 "Logi")
    let bgColor: NSColor       // 背景色
    let textColor: NSColor     // 文字色

    // MARK: - 内置品牌

    /// Logitech: 绿底黑字
    static let logi = BrandTagConfig(
        name: "Logi",
        bgColor: NSColor(calibratedRed: 0.0, green: 0.992, blue: 0.812, alpha: 1.0),  // #00FDCF
        textColor: NSColor(calibratedWhite: 0.15, alpha: 1.0)
    )
}

/// 品牌标签渲染工具
struct BrandTag {

    // MARK: - 判断

    /// 按键码是否属于某个品牌
    static func isLogiCode(_ code: UInt16) -> Bool {
        return LogitechCIDMap.isLogitechCode(code)
    }

    /// 快捷键 ID 是否属于某个品牌
    static func isLogiAction(_ identifier: String) -> Bool {
        return identifier.hasPrefix("logi")
    }

    /// 获取按键码对应的品牌配置 (nil = 非品牌按键)
    static func brandForCode(_ code: UInt16) -> BrandTagConfig? {
        if isLogiCode(code) { return .logi }
        return nil
    }

    /// 获取快捷键 ID 对应的品牌配置 (nil = 非品牌动作)
    static func brandForAction(_ identifier: String) -> BrandTagConfig? {
        if isLogiAction(identifier) { return .logi }
        return nil
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
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 2.5
        container.layer?.backgroundColor = brand.bgColor.cgColor
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
        brand.bgColor.setFill()
        bgPath.fill()
        let textRect = NSRect(x: padH, y: (height - textSize.height) / 2, width: textSize.width, height: textSize.height)
        (brand.name as NSString).draw(in: textRect, withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = false
        return image
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
            icon.draw(in: NSRect(x: tagSize.width + gap, y: (totalHeight - iconSize.height) / 2, width: iconSize.width, height: iconSize.height),
                      from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
