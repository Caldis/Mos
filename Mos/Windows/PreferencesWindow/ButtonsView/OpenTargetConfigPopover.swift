//
//  OpenTargetConfigPopover.swift
//  Mos
//  "打开应用…" 动作的配置 popover - 文件槽 + 参数 + 完成/取消
//

import Cocoa

final class OpenTargetConfigPopover: NSObject {

    // MARK: - Public callbacks
    var onCommit: ((OpenTargetPayload) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - State
    private var popover: NSPopover?
    private var existingPayload: OpenTargetPayload?

    // Captured selection
    private var selectedPath: String?
    private var selectedBundleID: String?
    private var selectedKind: OpenTargetKind = .file

    // Views
    private weak var fileSlot: FileSlotView?
    private weak var argsStack: NSStackView?     // 容器 NSStackView; 隐藏所有 arrangedSubviews 时整体塌缩到 0 高
    private weak var argsCaption: NSView?
    private weak var argsField: NSTextField?
    private weak var doneButton: NSButton?
    private weak var staleBanner: NSView?

    // Layout constants
    private static let contentWidth: CGFloat = 320
    private static let padding: CGFloat = 16
    private static let slotHeight: CGFloat = 76

    private struct PickedFile {
        let path: String
        let bundleID: String?
        let kind: OpenTargetKind
    }

    // MARK: - Show

    func show(at sourceView: NSView, existing: OpenTargetPayload?) {
        hide()
        self.existingPayload = existing
        self.selectedPath = existing?.path
        self.selectedBundleID = existing?.bundleID
        self.selectedKind = existing?.kind ?? .file

        let popover = NSPopover()
        popover.behavior = .applicationDefined  // 不自动关闭, 必须显式 close
        popover.contentViewController = makeViewController(initialArgs: existing?.arguments ?? "")
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        self.popover = popover

        // Initial state with stale detection
        if existing != nil, isCurrentSelectionResolvable() {
            applyFilledStateForCurrentSelection(animated: false)
        } else if existing != nil {
            // Stale: show warning, fall back to empty state
            staleBanner?.isHidden = false
            selectedPath = nil
            selectedBundleID = nil
            selectedKind = .file
            fileSlot?.setState(.empty, animated: false)
            doneButton?.isEnabled = false
            setArgumentsVisible(false, animated: false)
        } else {
            fileSlot?.setState(.empty, animated: false)
            setArgumentsVisible(false, animated: false)
        }
    }

    private func isCurrentSelectionResolvable() -> Bool {
        guard let path = selectedPath else { return false }
        if selectedKind == .application, let bundleID = selectedBundleID,
           NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }

    func hide() {
        popover?.close()
        popover = nil
    }

    // MARK: - View construction

    private func makeViewController(initialArgs: String) -> NSViewController {
        let vc = OpenTargetContentViewController()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Stale banner (initially hidden)
        let banner = makeStaleBanner()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.isHidden = true
        container.addSubview(banner)
        self.staleBanner = banner

        // File slot (empty state for now; filled state in Task 10)
        let slot = FileSlotView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.onClick = { [weak self] in self?.onFileSlotClicked() }
        slot.onClear = { [weak self] in self?.onFileSlotCleared() }
        slot.onDrop = { [weak self] url in
            guard let self = self, let picked = Self.resolvePickedFile(at: url) else { return }
            self.applyPickedFile(picked)
        }
        container.addSubview(slot)
        self.fileSlot = slot

        // Args caption (NSStackView 内部第一个 arrangedSubview)
        let captionRow = NSStackView()
        captionRow.orientation = .horizontal
        captionRow.spacing = 0
        captionRow.translatesAutoresizingMaskIntoConstraints = false
        let captionLabel = NSTextField(labelWithString: NSLocalizedString("open-target-arguments-label", comment: ""))
        captionLabel.font = NSFont.systemFont(ofSize: 11)
        captionLabel.textColor = NSColor.labelColor
        let captionSuffix = NSTextField(labelWithString: " " + NSLocalizedString("open-target-arguments-optional-suffix", comment: ""))
        captionSuffix.font = NSFont.systemFont(ofSize: 11)
        captionSuffix.textColor = NSColor.tertiaryLabelColor
        captionRow.addArrangedSubview(captionLabel)
        captionRow.addArrangedSubview(captionSuffix)
        self.argsCaption = captionRow

        // Args field (monospaced)
        let args = NSTextField()
        args.translatesAutoresizingMaskIntoConstraints = false
        args.bezelStyle = .roundedBezel
        args.placeholderString = NSLocalizedString("open-target-arguments-placeholder", comment: "")
        args.stringValue = initialArgs
        if #available(macOS 10.15, *) {
            args.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        } else {
            args.font = NSFont(name: "Menlo", size: 12) ?? NSFont.systemFont(ofSize: 12)
        }
        self.argsField = args

        // Args section (NSStackView): 隐藏所有 arrangedSubviews 时自身 intrinsic height = 0,
        // 这是 AppKit 唯一为"动态显隐布局"提供的原生机制. 用普通 NSView + 高度约束 toggle
        // 试过, fittingSize 会被内部 captionStack/args 的 required 约束牵扯, 算不到 0.
        let argsStack = NSStackView()
        argsStack.orientation = .vertical
        argsStack.alignment = .leading
        argsStack.spacing = 6
        argsStack.translatesAutoresizingMaskIntoConstraints = false
        argsStack.addArrangedSubview(captionRow)
        argsStack.addArrangedSubview(args)
        // 初始隐藏 (NSStackView 把 hidden arrangedSubviews 完全踢出布局)
        let initiallyHidden = (selectedPath == nil)
        captionRow.isHidden = initiallyHidden
        args.isHidden = initiallyHidden
        container.addSubview(argsStack)
        self.argsStack = argsStack

        // Buttons
        let cancel = NSButton(title: NSLocalizedString("open-target-cancel", comment: ""), target: self, action: #selector(onCancelButton))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        container.addSubview(cancel)

        let done = NSButton(title: NSLocalizedString("open-target-done", comment: ""), target: self, action: #selector(onDoneButton))
        done.translatesAutoresizingMaskIntoConstraints = false
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.isEnabled = (selectedPath != nil)
        container.addSubview(done)
        self.doneButton = done

        // Layout
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.contentWidth + Self.padding * 2),

            banner.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.padding),
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),

            slot.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 8),
            slot.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            slot.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            slot.heightAnchor.constraint(equalToConstant: Self.slotHeight),

            argsStack.topAnchor.constraint(equalTo: slot.bottomAnchor, constant: 12),
            argsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            argsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            args.heightAnchor.constraint(equalToConstant: 26),
            // 让 args field 占满 argsStack 宽度 (NSStackView .leading 对齐默认按 intrinsic 宽)
            args.widthAnchor.constraint(equalTo: argsStack.widthAnchor),

            done.topAnchor.constraint(equalTo: argsStack.bottomAnchor, constant: 16),
            done.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            done.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.padding),

            cancel.topAnchor.constraint(equalTo: done.topAnchor),
            cancel.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -8),
        ])

        vc.view = container
        return vc
    }

    private func makeStaleBanner() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6

        if #available(macOS 11.0, *), let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) {
            let imageView = NSImageView(image: symbol)
            imageView.contentTintColor = NSColor.systemOrange
            stack.addArrangedSubview(imageView)
        }

        let label = NSTextField(labelWithString: NSLocalizedString("open-target-stale-warning", comment: ""))
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.systemOrange
        stack.addArrangedSubview(label)

        return stack
    }

    // MARK: - Interactions (placeholders for Tasks 10-11)

    private func onFileSlotClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("open-target-panel-prompt", comment: "")
        panel.message = NSLocalizedString("open-target-panel-message", comment: "")
        // 不限制扩展名: 接受 .app, .sh, .py, 任意可执行文件

        guard let popoverWindow = popover?.contentViewController?.view.window else {
            // Fallback: 模态运行
            if panel.runModal() == .OK, let url = panel.url, let picked = Self.resolvePickedFile(at: url) {
                applyPickedFile(picked)
            }
            return
        }
        panel.beginSheetModal(for: popoverWindow) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            if let picked = Self.resolvePickedFile(at: url) {
                self.applyPickedFile(picked)
            }
        }
    }

    /// 解析任意文件 URL 为待保存的字段集; 返回 nil 表示路径无效.
    /// 推断规则:
    /// - .app 扩展名 → .application (同时取 bundleID)
    /// - 可执行位 set 的非 .app → .script (Process 运行)
    /// - 其它 → .file (NSWorkspace.open 用默认 app 打开)
    private static func resolvePickedFile(at url: URL) -> PickedFile? {
        var isDirectory: ObjCBool = false
        let isApp = url.pathExtension.lowercased() == "app"
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue || isApp else { return nil }
        if isApp {
            let bundleID = Bundle(url: url)?.bundleIdentifier
            return PickedFile(path: url.path, bundleID: bundleID, kind: .application)
        }
        if FileManager.default.isExecutableFile(atPath: url.path) {
            return PickedFile(path: url.path, bundleID: nil, kind: .script)
        }
        return PickedFile(path: url.path, bundleID: nil, kind: .file)
    }

    private func applyPickedFile(_ picked: PickedFile) {
        selectedPath = picked.path
        selectedBundleID = picked.bundleID
        selectedKind = picked.kind
        staleBanner?.isHidden = true
        applyFilledStateForCurrentSelection(animated: true)
    }

    private func applyFilledStateForCurrentSelection(animated: Bool) {
        guard let path = selectedPath else {
            fileSlot?.setState(.empty, animated: animated)
            doneButton?.isEnabled = false
            setArgumentsVisible(false, animated: animated)
            return
        }
        let url = URL(fileURLWithPath: path)
        let workspace = NSWorkspace.shared
        let icon = workspace.icon(forFile: url.path)
        let title: String = {
            if selectedKind == .application, let bundle = Bundle(url: url) {
                return bundle.localizedDisplayName
                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
            }
            return url.lastPathComponent
        }()
        let content = FileSlotView.FilledContent(icon: icon, title: title, subtitle: path)
        fileSlot?.setState(.filled(content), animated: animated)
        doneButton?.isEnabled = true
        // .file 不支持参数 (NSWorkspace.open 不接受 argv), 隐藏 args 区域避免误导.
        let supportsArgs = (selectedKind == .application || selectedKind == .script)
        setArgumentsVisible(supportsArgs, animated: animated)
    }

    private func onFileSlotCleared() {
        selectedPath = nil
        selectedBundleID = nil
        selectedKind = .file
        staleBanner?.isHidden = true
        fileSlot?.setState(.empty, animated: true)
        doneButton?.isEnabled = false
        setArgumentsVisible(false, animated: true)
    }

    private func setArgumentsVisible(_ visible: Bool, animated: Bool) {
        // 始终瞬时切换. NSPopover 不实现 NSAnimatablePropertyContainer, contentSize
        // 没有任何动画通道; 任何内部渐变都会与 popover 框架瞬移脱节而撕裂. 同帧瞬时
        // 完成 → 视觉上没有"先后", 谈不上跳. fileSlot 内部 250ms 渐变保留 (slot 内的
        // alpha 变化与 popover 框架无关).
        _ = animated  // intentionally unused

        // 注: 不在这里管 doneButton.isEnabled. done 的启用条件是 "selectedPath != nil",
        // 与 args 显隐无关 (kind=.file 时 args 被隐藏但 done 仍应可用).
        // doneButton.isEnabled 由调用方 (applyFilledStateForCurrentSelection / onFileSlotCleared) 管理.

        // 通过 NSStackView 的 hidden arrangedSubviews 机制塌缩布局: hidden 时整个 stack
        // intrinsic height = 0, 容器 fittingSize 自然下降. 这是 AppKit 唯一保证 fittingSize
        // 真实反映"有/无内容"的方式 (普通 NSView + 高度约束 toggle 会被内部 required 约束牵扯).
        argsCaption?.isHidden = !visible
        argsField?.isHidden = !visible

        guard let view = popover?.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        popover?.contentSize = view.fittingSize
    }

    @objc private func onDoneButton() {
        guard let path = selectedPath, let argsField = argsField else { return }
        let payload = OpenTargetPayload(
            path: path,
            bundleID: selectedBundleID,
            arguments: argsField.stringValue,
            kind: selectedKind
        )
        onCommit?(payload)
        hide()
    }

    @objc private func onCancelButton() {
        onCancel?()
        hide()
    }
}

// MARK: - File slot view (empty + filled states with crossfade)

final class FileSlotView: NSView {

    var onClick: (() -> Void)?
    var onClear: (() -> Void)?
    /// Drop callback exposed to the popover.
    var onDrop: ((URL) -> Void)?

    private(set) var state: State = .empty

    enum State: Equatable {
        case empty
        case filled(FilledContent)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.empty, .empty):
                return true
            case (.filled(let lhsContent), .filled(let rhsContent)):
                return lhsContent == rhsContent
            default:
                return false
            }
        }
    }

    struct FilledContent: Equatable {
        let icon: NSImage?
        let title: String
        let subtitle: String

        static func == (lhs: FilledContent, rhs: FilledContent) -> Bool {
            return lhs.icon === rhs.icon &&
                   lhs.title == rhs.title &&
                   lhs.subtitle == rhs.subtitle
        }
    }

    private var emptyView: NSView!
    private var filledView: NSView!
    private let borderLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isDragHighlighting = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = false
        borderLayer.fillColor = nil
        borderLayer.lineDashPattern = [5, 4]
        layer?.addSublayer(borderLayer)
        registerForDraggedTypes([.fileURL])

        emptyView = makeEmptyView()
        filledView = makeFilledView()
        emptyView.alphaValue = 1
        filledView.alphaValue = 0
        // 用 auto-layout edge anchor 钉死到父视图四边. 默认 translatesAutoresizingMask
        // = true 会从初始 frame=.zero 派生 width=0/height=0 隐式约束, 与内部 icon
        // 的 required 约束 (leading=12, width=36) 冲突, 在 console 里刷一堆
        // "Conflicting constraints" 警告.
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        filledView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyView)
        addSubview(filledView)
        NSLayoutConstraint.activate([
            emptyView.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyView.topAnchor.constraint(equalTo: topAnchor),
            emptyView.bottomAnchor.constraint(equalTo: bottomAnchor),
            filledView.leadingAnchor.constraint(equalTo: leadingAnchor),
            filledView.trailingAnchor.constraint(equalTo: trailingAnchor),
            filledView.topAnchor.constraint(equalTo: topAnchor),
            filledView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyEmptyAppearance()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHovering else { return }
        isHovering = true
        refreshAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isHovering else { return }
        isHovering = false
        refreshAppearance(animated: true)
    }

    /// 重新计算 + 应用当前外观, 可选 CALayer 隐式动画.
    private func refreshAppearance(animated: Bool) {
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        switch state {
        case .empty: applyEmptyAppearance()
        case .filled: applyFilledAppearance()
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        // 在每次 layout 后校准 anchor: AppKit 在 wantsLayer 视图被 re-add 到新 superview /
        // 其它 layer 重建场景下会把 anchorPoint 重置回 (0,0); 不在此处补偿, 接下来的
        // scale 动画就会从角落起算. ensureCenterAnchor 是幂等的.
        ensureCenterAnchor()
        // emptyView / filledView 的 frame 由 setupView 里的 edge anchor 约束驱动,
        // 不再手动设置 (会与 auto-layout 打架).
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
    }

    override func mouseDown(with event: NSEvent) {
        // Don't propagate clicks on the clear button
        let point = convert(event.locationInWindow, from: nil)
        if let clearBtn = filledView.viewWithTag(99), clearBtn.frame.contains(point), case .filled = state {
            return
        }
        onClick?()
    }

    // MARK: State control

    func setState(_ newState: State, animated: Bool = true) {
        guard newState != state else { return }
        state = newState

        let (showView, hideView): (NSView, NSView) = {
            switch newState {
            case .empty: return (emptyView, filledView)
            case .filled(let content):
                applyFilledContent(content)
                return (filledView, emptyView)
            }
        }()

        switch newState {
        case .empty: applyEmptyAppearance()
        case .filled: applyFilledAppearance()
        }

        if animated {
            showView.alphaValue = 0
            showView.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.98, y: 0.98))
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                showView.animator().alphaValue = 1
                showView.animator().layer?.setAffineTransform(.identity)
                hideView.animator().alphaValue = 0
            })
        } else {
            showView.alphaValue = 1
            showView.layer?.setAffineTransform(.identity)
            hideView.alphaValue = 0
        }
    }

    // MARK: Appearance

    fileprivate func applyEmptyAppearance() {
        if isDragHighlighting {
            borderLayer.lineWidth = 1.2
            borderLayer.lineDashPattern = [5, 4]
            borderLayer.strokeColor = accentColor.withAlphaComponent(0.45).cgColor
            layer?.backgroundColor = accentColor.withAlphaComponent(0.05).cgColor
        } else {
            borderLayer.lineWidth = 1
            borderLayer.lineDashPattern = [5, 4]
            let borderAlpha: CGFloat = isHovering ? 0.55 : 0.32
            let bgAlpha: CGFloat = isHovering ? 0.07 : 0.04
            borderLayer.strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(borderAlpha).cgColor
            layer?.backgroundColor = NSColor.gray.withAlphaComponent(bgAlpha).cgColor
        }
        toolTip = NSLocalizedString("open-target-empty-tooltip", comment: "")
    }

    fileprivate func applyFilledAppearance() {
        if isDragHighlighting {
            borderLayer.lineWidth = 1.2
            borderLayer.lineDashPattern = [5, 4]
            borderLayer.strokeColor = accentColor.withAlphaComponent(0.45).cgColor
            layer?.backgroundColor = accentColor.withAlphaComponent(0.05).cgColor
        } else {
            borderLayer.lineWidth = 1
            borderLayer.lineDashPattern = [5, 4]
            let borderAlpha: CGFloat = isHovering ? 0.5 : 0.24
            let bgAlpha: CGFloat = isHovering ? 0.06 : 0.03
            borderLayer.strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(borderAlpha).cgColor
            layer?.backgroundColor = NSColor.gray.withAlphaComponent(bgAlpha).cgColor
        }
        toolTip = NSLocalizedString("open-target-filled-tooltip", comment: "")
    }

    // MARK: Empty subview

    private func makeEmptyView() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let placeholder = NSImageView()
        placeholder.image = Self.placeholderImage()
        placeholder.imageScaling = .scaleProportionallyUpOrDown
        if #available(macOS 10.14, *) {
            placeholder.contentTintColor = NSColor.tertiaryLabelColor
        }
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        let primary = NSTextField(labelWithString: NSLocalizedString("open-target-empty-primary", comment: ""))
        primary.font = NSFont.systemFont(ofSize: 13)
        primary.textColor = NSColor.labelColor

        let secondary = NSTextField(labelWithString: NSLocalizedString("open-target-empty-secondary", comment: ""))
        secondary.font = NSFont.systemFont(ofSize: 11)
        secondary.textColor = NSColor.tertiaryLabelColor

        let stack = NSStackView(views: [placeholder, primary, secondary])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            placeholder.widthAnchor.constraint(equalToConstant: 18),
            placeholder.heightAnchor.constraint(equalToConstant: 18),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private static func placeholderImage() -> NSImage? {
        if #available(macOS 11.0, *),
           let symbol = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) {
            symbol.isTemplate = true
            return symbol
        }
        let icon = NSWorkspace.shared.icon(forFileType: "app")
        icon.size = NSSize(width: 24, height: 24)
        return icon
    }

    // MARK: Filled subview

    private weak var filledIcon: NSImageView?
    private weak var filledTitle: NSTextField?
    private weak var filledSubtitle: NSTextField?

    private func makeFilledView() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)
        self.filledIcon = icon

        let title = NSTextField(labelWithString: "")
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.textColor = NSColor.labelColor
        self.filledTitle = title

        let subtitle = NSTextField(labelWithString: "")
        subtitle.font = NSFont.systemFont(ofSize: 10.5)
        subtitle.textColor = NSColor.tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        self.filledSubtitle = subtitle

        // 用 NSStackView 包裹 title+subtitle, 整体 centerY 对齐到容器, 与左侧图标的
        // centerY 同轴; 直接给 title 设 topAnchor=topConstant 会让文本组偏上, 视觉
        // 与图标错位.
        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        let clearBtn = HoverableClearButton()
        clearBtn.tag = 99  // used in mouseDown hit test
        clearBtn.bezelStyle = .inline
        clearBtn.isBordered = false
        if #available(macOS 11.0, *) {
            clearBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        } else {
            clearBtn.title = "✕"
        }
        clearBtn.toolTip = NSLocalizedString("open-target-clear-tooltip", comment: "")
        clearBtn.target = self
        clearBtn.action = #selector(onClearClicked)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(clearBtn)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),

            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: clearBtn.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            clearBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            clearBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            clearBtn.widthAnchor.constraint(equalToConstant: 16),
            clearBtn.heightAnchor.constraint(equalToConstant: 16),
        ])

        return container
    }

    private func applyFilledContent(_ content: FilledContent) {
        filledIcon?.image = content.icon
        filledTitle?.stringValue = content.title
        filledSubtitle?.stringValue = content.subtitle
        toolTip = "\(content.subtitle)\n\(NSLocalizedString("open-target-filled-tooltip", comment: ""))"
    }

    @objc private func onClearClicked() {
        onClear?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let first = firstDraggedFileURL(sender), isAcceptedDraggedFile(first) else {
            return []
        }
        isDragHighlighting = true
        refreshAppearance(animated: true)
        animateScale(to: 1.02)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        revertDragVisual()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { revertDragVisual() }
        guard let first = firstDraggedFileURL(sender), isAcceptedDraggedFile(first) else {
            return false
        }
        onDrop?(first)
        return true
    }

    private func firstDraggedFileURL(_ sender: NSDraggingInfo) -> URL? {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return nil
        }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return nil
        }
        return urls.first
    }

    private func isAcceptedDraggedFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let isApp = url.pathExtension.lowercased() == "app"
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue || isApp
    }

    private var accentColor: NSColor {
        if #available(macOS 10.14, *) {
            return NSColor.controlAccentColor
        }
        return NSColor.alternateSelectedControlColor
    }

    private func animateScale(to scale: CGFloat) {
        guard let layer = layer else { return }
        // Apple 实际行为: effective_transform = T(anchor_own) × t_user × T(-anchor_own).
        // 试图用复合变换在 anchor=(0,0) 时模拟中心枢轴会被这层包裹反向抵消.
        // 唯一可靠路径: 把 anchor 真实改成 (0.5, 0.5), 同步补偿 position 保证 frame 不跳动,
        // 之后直接 CATransform3DMakeScale 就是中心枢轴的简单 scale.
        ensureCenterAnchor()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            layer.transform = abs(scale - 1.0) < 0.001
                ? CATransform3DIdentity
                : CATransform3DMakeScale(scale, scale, 1)
        }
    }

    /// 把 layer.anchorPoint 校准到 (0.5, 0.5), 同时补偿 position 让 frame 不视觉跳动.
    /// 幂等: 已在中心则跳过. 在 layout() 和 animateScale() 入口都调用, 对抗 AppKit
    /// 在 view 被 re-add / layer 被重建等场景下重置 anchor.
    private func ensureCenterAnchor() {
        guard let layer = layer else { return }
        let target = CGPoint(x: 0.5, y: 0.5)
        if abs(layer.anchorPoint.x - target.x) < 0.001 &&
           abs(layer.anchorPoint.y - target.y) < 0.001 {
            return
        }
        let bounds = layer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }  // frame 还未确定时跳过
        let oldAnchor = layer.anchorPoint
        layer.anchorPoint = target
        layer.position = CGPoint(
            x: layer.position.x + (target.x - oldAnchor.x) * bounds.width,
            y: layer.position.y + (target.y - oldAnchor.y) * bounds.height
        )
    }

    private func revertDragVisual() {
        isDragHighlighting = false
        animateScale(to: 1.0)
        refreshAppearance(animated: true)
    }
}

// MARK: - Content view controller

/// 普通 NSViewController, 不在 viewDidLayout 里自动设 preferredContentSize.
///
/// 之前这里曾在 viewDidLayout 同步 preferredContentSize, 但发现:
/// 1. setArgumentsVisible 里 layoutSubtreeIfNeeded() 会触发 viewDidLayout
/// 2. viewDidLayout 把 preferredContentSize 设到当前 fittingSize
/// 3. 这条路径与我显式 popover.contentSize = view.fittingSize 抢同一个目标值;
///    NSPopover 内部对二者协同有未文档化的状态机, 实测会让 popover 在收回时卡尺寸.
/// 现在只保留 setArgumentsVisible 里的显式赋值作为唯一权威源.
private final class OpenTargetContentViewController: NSViewController {}

// MARK: - Hoverable clear button

/// 文件槽内的 ✕ 按钮: 默认 tertiaryLabelColor, hover 时切到 systemRed,
/// 通过 NSTrackingArea 监听 mouse enter/exit 触发 contentTintColor 变化.
private final class HoverableClearButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        applyTint(hovering: false, animated: false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyTint(hovering: false, animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        applyTint(hovering: true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        applyTint(hovering: false, animated: true)
    }

    private func applyTint(hovering: Bool, animated: Bool) {
        guard #available(macOS 10.14, *) else { return }
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        contentTintColor = hovering ? NSColor.systemRed : NSColor.tertiaryLabelColor
        CATransaction.commit()
    }
}
