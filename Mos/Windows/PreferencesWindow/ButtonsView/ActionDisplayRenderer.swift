//
//  ActionDisplayRenderer.swift
//  Mos
//
//  Created by Mos on 2026/4/12.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

/// Selector 显示图像的双图载体: `raw` 给 NSMenu 展开行用 (NSMenuItemCell 自带图文间距),
/// `padded` 给 NSPopUpButton button face 用 (NSPopUpButtonCell 不给图文间距, 需位图 padding 填补).
///
/// **why**: button face 与 menu 展开第一行默认共用 `placeholderItem.image`,
/// 但两者所在的 cell 类型不同, 间距来源不同 — 用同一张图永远会差一个 AppKit cell 默认间距.
/// 拆成 raw/padded 双图, 配合 `cell.usesItemFromMenu = false` 让两侧分别取图,
/// button face (位图右侧 padding) 与 menu 展开行 (raw + NSMenuItemCell 自带间距) 视觉对齐.
///
/// padding 量见 `prepared(_:)` 内 `spacing` (视觉调试得到, 略小于 NSMenuItemCell 默认间距).
///
/// 唯一构造方式 `prepared(_:)`: 包装裸 NSImage, 自动派生 raw 与 padded.
struct SelectorImage {
    fileprivate let raw: NSImage
    fileprivate let padded: NSImage

    private init(raw: NSImage, padded: NSImage) {
        self.raw = raw
        self.padded = padded
    }

    static func prepared(_ image: NSImage) -> SelectorImage {
        let spacing: CGFloat = 3.7
        let originalSize = image.size
        let newSize = NSSize(width: originalSize.width + spacing, height: originalSize.height)

        let paddedImage = NSImage(size: newSize)
        paddedImage.lockFocus()
        image.draw(
            in: NSRect(x: 0, y: 0, width: originalSize.width, height: originalSize.height),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .sourceOver,
            fraction: 1.0
        )
        paddedImage.unlockFocus()
        paddedImage.isTemplate = image.isTemplate
        return SelectorImage(raw: image, padded: paddedImage)
    }
}

struct ActionDisplayRenderer {

    // 关于 selector 图文间距 (button face vs menu 展开第一行):
    // - placeholderItem.image = raw (NSMenuItemCell 自带间距, 渲染 menu 行)
    // - cell.menuItem.image = padded (NSPopUpButtonCell 无自带间距, 用位图 padding)
    // - cell.usesItemFromMenu = false 解耦两条通道
    // 新加 case 把 NSImage 喂给 SelectorImage.prepared, apply() 会自动两边分发.
    func render(_ presentation: ActionPresentation, into popupButton: NSPopUpButton) {
        guard let menu = popupButton.menu,
              let placeholderItem = menu.items.first else {
            return
        }

        let renderBody = {
            renderResolved(presentation, placeholderItem: placeholderItem, popupButton: popupButton)
        }
        if #available(macOS 10.14, *) {
            let previousAppearance = NSAppearance.current
            NSAppearance.current = popupButton.effectiveAppearance
            defer { NSAppearance.current = previousAppearance }
            renderBody()
        } else {
            renderBody()
        }
    }

    private func renderResolved(
        _ presentation: ActionPresentation,
        placeholderItem: NSMenuItem,
        popupButton: NSPopUpButton
    ) {
        switch presentation.kind {
        case .unbound, .recordingPrompt:
            apply(title: presentation.title, image: nil, placeholderItem: placeholderItem, popupButton: popupButton)

        case .namedAction:
            let baseImage = createSymbolImage(named: presentation.symbolName)
            let withTag = prefixedImageIfNeeded(baseImage, tag: presentation.tag)
            let prepared = withTag.map { SelectorImage.prepared($0) }
            apply(title: presentation.title, image: prepared, placeholderItem: placeholderItem, popupButton: popupButton)

        case .keyCombo:
            // keyCombo 的内容全部在 badge image 里; 不要给 button face 单独缩放,
            // 否则 menu 第一行和 button face 的可见 badge 尺寸会分裂.
            let badgeImage = Self.createBadgeImage(from: presentation.badgeComponents)
            let withTag = prefixedImageIfNeeded(badgeImage, tag: presentation.tag)
            let prepared = withTag.map { SelectorImage.prepared($0) }
            apply(
                title: presentation.title,
                image: prepared,
                placeholderItem: placeholderItem,
                popupButton: popupButton,
                usePaddedButtonFaceImage: false
            )

        case .openTarget:
            let resizedImage = presentation.image.map { Self.resizeForBadge($0) }
            let prepared = resizedImage.map { SelectorImage.prepared($0) }
            apply(title: presentation.title, image: prepared, placeholderItem: placeholderItem, popupButton: popupButton)
        }
    }

    /// Resize an arbitrary NSImage to match the visual size of system shortcut icons (badge height 17pt).
    private static func resizeForBadge(_ image: NSImage) -> NSImage {
        let badgeHeight: CGFloat = 17
        let originalSize = image.size
        guard originalSize.height > 0 else { return image }
        let scale = badgeHeight / originalSize.height
        let newSize = NSSize(width: originalSize.width * scale, height: badgeHeight)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .sourceOver,
                   fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    private func apply(
        title: String,
        image: SelectorImage?,
        placeholderItem: NSMenuItem,
        popupButton: NSPopUpButton,
        usePaddedButtonFaceImage: Bool = true
    ) {
        // menu 展开第一行 — placeholderItem (raw, 由 NSMenuItemCell 提供间距)
        placeholderItem.title = title
        placeholderItem.image = image.map { Self.menuAlignedImage($0.raw) }

        // button face — cell.menuItem 走独立 NSMenuItem (padded, 位图 padding 填补 cell 无间距).
        // cell.usesItemFromMenu = false 切断 cell.menuItem 与 selectedItem 的自动同步;
        // NSPopUpButtonCell 真正驱动 button face 的是 cell.menuItem, 不是 cell.image / cell.title,
        // 必须显式赋值, 否则 button face 空白.
        //
        // ⚠️ 不要换回 `synchronizeTitleAndSelectedItem()` 或 `popupButton.usesItemFromMenu` (后者是
        // macOS 15+ API, 且会重新同步 cell.menuItem ← selectedItem, 推翻 padded vs raw 解耦).
        if let cell = popupButton.cell as? NSPopUpButtonCell {
            cell.usesItemFromMenu = false
            let buttonFaceItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            // button face 与 menu 第一行走不同 cell drawing 路径 (NSPopUpButtonCell vs NSMenuItemCell),
            // baseline 天然差 ~1pt (实测得到, 不深究 AppKit 内部 layout 算法);
            // 用 .baselineOffset 把 button face 文字向上抬 1pt 对齐 menu 行视觉.
            buttonFaceItem.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.baselineOffset: 1.0]
            )
            buttonFaceItem.image = image.map {
                Self.menuAlignedImage(usePaddedButtonFaceImage ? $0.padded : $0.raw)
            }
            cell.menuItem = buttonFaceItem
        }
        popupButton.imagePosition = .imageLeft
        popupButton.selectItem(at: 0)
    }

    /// 把图统一拉到 18pt 高 (NSMenuItem 标准行高), 仅做垂直居中, **不影响水平间距**.
    /// 水平间距: raw (menu 行) 由 NSMenuItemCell 自带间距负责; padded (button face) 由
    /// SelectorImage.prepared 的位图 padding 负责.
    private static func menuAlignedImage(_ image: NSImage) -> NSImage {
        let targetHeight: CGFloat = 18
        let imageSize = image.size
        guard imageSize.height > 0, imageSize.height <= targetHeight else { return image }

        let imageY = (targetHeight - imageSize.height) / 2
        let alignedSize = NSSize(width: imageSize.width, height: targetHeight)
        let alignedImage = NSImage(size: alignedSize)
        alignedImage.lockFocus()
        image.draw(
            in: NSRect(x: 0, y: imageY, width: imageSize.width, height: imageSize.height),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .sourceOver,
            fraction: 1.0
        )
        alignedImage.unlockFocus()
        alignedImage.isTemplate = image.isTemplate

        return alignedImage
    }

    private func createSymbolImage(named symbolName: String?) -> NSImage? {
        guard let symbolName else { return nil }
        guard #available(macOS 11.0, *) else { return nil }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    private func prefixedImageIfNeeded(_ image: NSImage?, tag: BrandTagConfig?) -> NSImage? {
        guard let tag else { return image }
        return BrandTag.createPrefixedImage(brand: tag, original: image)
    }

    static func createBadgeImage(from components: [String]) -> NSImage {
        let fontSize: CGFloat = 9
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let plusFont = NSFont.systemFont(ofSize: fontSize)
        let badgeHeight: CGFloat = 17
        let cornerRadius: CGFloat = 3
        let hPadding: CGFloat = 5
        let plusSpacing: CGFloat = 3
        let iconSize: CGFloat = 11
        let iconTrailingGap: CGFloat = 4
        let trailingSafetyPadding: CGFloat = 2.5
        let keyboardImage: NSImage?
        if #available(macOS 11.0, *) {
            let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            keyboardImage = symbol?.withSymbolConfiguration(config) ?? symbol
        } else {
            keyboardImage = nil
        }

        struct BadgeMetrics {
            let text: String
            let textSize: NSSize
            let badgeWidth: CGFloat
        }

        var badges: [BadgeMetrics] = []
        var totalWidth: CGFloat = 0

        for (index, component) in components.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = (component as NSString).size(withAttributes: attrs)
            let badgeWidth = max(textSize.width + hPadding * 2, badgeHeight)
            badges.append(BadgeMetrics(text: component, textSize: textSize, badgeWidth: badgeWidth))
            totalWidth += badgeWidth
            if index > 0 {
                let plusSize = ("+" as NSString).size(withAttributes: [.font: plusFont])
                totalWidth += plusSpacing * 2 + plusSize.width
            }
        }

        var iconWidth: CGFloat = 0
        if let keyboardImage {
            iconWidth = keyboardImage.size.width + iconTrailingGap
        }
        totalWidth += iconWidth

        // keyCombo 的主要内容在这张 badge image 里, 最后一个 badge 不能贴着 bitmap 右边界画,
        // 否则 button face/menu 的 clip 都可能吃掉最后一列像素.
        let imageSize = NSSize(width: ceil(totalWidth + trailingSafetyPadding), height: badgeHeight)
        return NSImage(size: imageSize, flipped: false) { canvasRect in
            NSColor.clear.setFill()
            canvasRect.fill(using: .copy)

            var x: CGFloat = 0

            if let keyboardImage {
                let symbolSize = keyboardImage.size
                let iconY = (badgeHeight - symbolSize.height) / 2
                let iconRect = NSRect(x: x, y: iconY, width: symbolSize.width, height: symbolSize.height)
                keyboardImage.draw(in: iconRect)
                NSColor.labelColor.set()
                iconRect.fill(using: .sourceAtop)
                x += symbolSize.width + iconTrailingGap
            }

            let bgColor = Self.isDarkModeForCurrentAppearance()
                ? NSColor(calibratedWhite: 0.5, alpha: 0.2)
                : NSColor(calibratedWhite: 0.0, alpha: 0.1)
            let textColor = NSColor.labelColor

            for (index, badge) in badges.enumerated() {
                if index > 0 {
                    let plusAttrs: [NSAttributedString.Key: Any] = [
                        .font: plusFont,
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                    let plusSize = ("+" as NSString).size(withAttributes: plusAttrs)
                    x += plusSpacing
                    let plusY = (badgeHeight - plusSize.height) / 2
                    ("+" as NSString).draw(at: NSPoint(x: x, y: plusY), withAttributes: plusAttrs)
                    x += plusSize.width + plusSpacing
                }

                let badgeRect = NSRect(x: x, y: 0, width: badge.badgeWidth, height: badgeHeight)
                let path = NSBezierPath(roundedRect: badgeRect, xRadius: cornerRadius, yRadius: cornerRadius)
                bgColor.setFill()
                path.fill()

                let textAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                ]
                let textX = x + (badge.badgeWidth - badge.textSize.width) / 2
                let textY = (badgeHeight - badge.textSize.height) / 2
                (badge.text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttrs)

                x += badge.badgeWidth
            }
            return true
        }
    }

    private static func isDarkModeForCurrentAppearance() -> Bool {
        if #available(macOS 10.14, *) {
            return NSAppearance.current.bestMatch(
                from: [
                    .darkAqua,
                    .vibrantDark,
                    .accessibilityHighContrastDarkAqua,
                    .accessibilityHighContrastVibrantDark
                ]
            ) != nil
        }
        return Utils.isDarkMode(for: nil)
    }
}
