//
//  ToastContentView.swift
//  Mos
//  Toast 内容视图 - 毛玻璃背景 + 图标 + 消息文本 + 强调条
//

import Cocoa

/// Toast 内容视图 (模块内部使用)
///
/// 使用 NSVisualEffectView 实现毛玻璃背景, 包含可选图标和文本标签。
class ToastContentView: NSView {

    // MARK: - Subviews

    private let effectView: NSVisualEffectView
    private let iconView: NSImageView
    private let messageLabel: NSTextField
    private let accentIndicator: NSView

    // MARK: - Constants

    private let cornerRadius: CGFloat = 10
    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 8
    private let iconSize: CGFloat = 20
    private let iconMessageSpacing: CGFloat = 8
    private let accentIndicatorWidth: CGFloat = 3

    // MARK: - State

    private var hasIcon: Bool = false
    private var hasAccent: Bool = false
    private var icon: NSImage?
    private var accentColor: NSColor?
    private var showsAccentIndicator: Bool = true
    private var dragStartScreenLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    // MARK: - Initialization

    init(message: String, icon: NSImage?, accentColor: NSColor?, showsAccentIndicator: Bool) {
        effectView = NSVisualEffectView()
        iconView = NSImageView()
        messageLabel = NSTextField(labelWithString: "")
        accentIndicator = NSView()

        super.init(frame: .zero)

        setupEffectView()
        setupIconView()
        setupMessageLabel()
        setupAccentIndicator()
        setupLayout()

        update(message: message, icon: icon, accentColor: accentColor, showsAccentIndicator: showsAccentIndicator)
    }

    required init?(coder: NSCoder) {
        fatalError("ToastContentView does not support Interface Builder")
    }

    // MARK: - Setup

    private func setupEffectView() {
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.state = .active
        effectView.blendingMode = .behindWindow

        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
            effectView.appearance = NSAppearance(named: .vibrantDark)
        } else {
            effectView.material = .dark
        }

        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
    }

    private func setupIconView() {
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isHidden = true
        effectView.addSubview(iconView)
    }

    private func setupMessageLabel() {
        messageLabel.font = NSFont.systemFont(ofSize: 13)
        messageLabel.textColor = NSColor.labelColor
        messageLabel.backgroundColor = .clear
        messageLabel.isBezeled = false
        messageLabel.isEditable = false
        messageLabel.isSelectable = false
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.cell?.truncatesLastVisibleLine = true
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(messageLabel)
    }

    private func setupAccentIndicator() {
        accentIndicator.wantsLayer = true
        accentIndicator.layer?.cornerRadius = accentIndicatorWidth / 2.0
        accentIndicator.isHidden = true
        accentIndicator.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(accentIndicator)
    }

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            accentIndicator.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 5),
            accentIndicator.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            accentIndicator.widthAnchor.constraint(equalToConstant: accentIndicatorWidth),
            accentIndicator.heightAnchor.constraint(equalTo: effectView.heightAnchor, multiplier: 0.5),

            iconView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            messageLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: verticalPadding),
            messageLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -verticalPadding),
            messageLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -horizontalPadding),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
    }

    // MARK: - Update Content

    func update(message: String, icon: NSImage?, accentColor: NSColor?, showsAccentIndicator: Bool) {
        messageLabel.stringValue = message
        self.icon = icon
        self.accentColor = accentColor
        self.showsAccentIndicator = showsAccentIndicator

        if let img = icon {
            let tintedIcon = tintImage(img, color: accentColor ?? NSColor.white)
            iconView.image = tintedIcon
            iconView.isHidden = false
            hasIcon = true
        } else {
            iconView.image = nil
            iconView.isHidden = true
            hasIcon = false
        }

        if let color = accentColor, showsAccentIndicator {
            accentIndicator.layer?.backgroundColor = color.cgColor
            accentIndicator.isHidden = false
            hasAccent = true
        } else {
            accentIndicator.isHidden = true
            hasAccent = false
        }

        updateMessageLeadingConstraint()
    }

    func setShowsAccentIndicator(_ showsAccentIndicator: Bool) {
        update(
            message: messageLabel.stringValue,
            icon: icon,
            accentColor: accentColor,
            showsAccentIndicator: showsAccentIndicator
        )
    }

    // MARK: - Dynamic Layout

    private var messageLeadingConstraint: NSLayoutConstraint?

    private func updateMessageLeadingConstraint() {
        if let old = messageLeadingConstraint {
            old.isActive = false
        }

        let leadingOffset: CGFloat
        if hasIcon {
            leadingOffset = horizontalPadding + iconSize + iconMessageSpacing
        } else if hasAccent {
            leadingOffset = 5 + accentIndicatorWidth + horizontalPadding
        } else {
            leadingOffset = horizontalPadding
        }

        let constraint = messageLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: leadingOffset)
        constraint.isActive = true
        messageLeadingConstraint = constraint
    }

    // MARK: - Image Tinting

    private func tintImage(_ image: NSImage, color: NSColor) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    // MARK: - Style Helpers (moved from ToastWindow)

    /// 根据样式返回默认图标
    static func defaultIcon(for style: Toast.Style) -> NSImage? {
        if #available(macOS 11.0, *) {
            let symbolName: String
            switch style {
            case .info:    symbolName = "info.circle.fill"
            case .success: symbolName = "checkmark.circle.fill"
            case .warning: symbolName = "exclamationmark.triangle.fill"
            case .error:   symbolName = "xmark.circle.fill"
            }
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
        switch style {
        case .info:    return NSImage(named: NSImage.infoName)
        case .success: return NSImage(named: NSImage.statusAvailableName)
        case .warning: return NSImage(named: NSImage.cautionName)
        case .error:   return NSImage(named: NSImage.stopProgressFreestandingTemplateName)
        }
    }

    /// 根据样式返回强调色
    static func accentColor(for style: Toast.Style) -> NSColor? {
        switch style {
        case .info:    return NSColor(calibratedRed: 0.34, green: 0.66, blue: 0.96, alpha: 1.0)
        case .success: return NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0)
        case .warning: return NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.20, alpha: 1.0)
        case .error:   return NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.30, alpha: 1.0)
        }
    }

    // MARK: - Dragging

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        dragStartScreenLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window,
              let dragStartScreenLocation = dragStartScreenLocation,
              let dragStartWindowOrigin = dragStartWindowOrigin else {
            return
        }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - dragStartScreenLocation.x
        let deltaY = currentLocation.y - dragStartScreenLocation.y
        let targetOrigin = NSPoint(
            x: dragStartWindowOrigin.x + deltaX,
            y: dragStartWindowOrigin.y + deltaY
        )

        if let panel = window as? NSPanel {
            window.setFrameOrigin(
                ToastManager.shared.snappedOrigin(for: panel, proposedOrigin: targetOrigin)
            )
        } else {
            window.setFrameOrigin(targetOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let panel = window as? NSPanel {
            ToastManager.shared.saveAnchor(for: panel)
        }
        clearDragState()
    }

    private func clearDragState() {
        dragStartScreenLocation = nil
        dragStartWindowOrigin = nil
    }
}
