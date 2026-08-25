//
//  GestureTableCellView.swift
//  Mos
//  鼠标手势绑定表格单元格视图
//  Created by Claude on 2026/4/15.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

class GestureTableCellView: NSTableCellView, NSMenuDelegate {

    // MARK: - UI Components

    private var keyPreview: KeyPreview!

    // Movement popups (4 directions: ↑↓←→)
    private var upPopUp:    NSPopUpButton!
    private var downPopUp:  NSPopUpButton!
    private var leftPopUp:  NSPopUpButton!
    private var rightPopUp: NSPopUpButton!

    // Scroll popups (2 directions: ↑↓ only)
    private var scrollUpPopUp:   NSPopUpButton!
    private var scrollDownPopUp: NSPopUpButton!

    // MARK: - State

    /// Per-direction current movement action identifier (nil = unbound)
    private var currentActions: [GestureDirection: String?] = [
        .up: nil, .down: nil, .left: nil, .right: nil,
    ]

    /// Per-direction current scroll action identifier (nil = unbound)
    private var currentScrollActions: [GestureDirection: String?] = [
        .up: nil, .down: nil,
    ]

    // MARK: - Callbacks

    private var onMovementActionChanged: ((GestureDirection, SystemShortcut.Shortcut?) -> Void)?
    private var onScrollActionChanged:   ((GestureDirection, SystemShortcut.Shortcut?) -> Void)?
    private var onDeleteRequested: (() -> Void)?

    // MARK: - Tags
    // Movement popup tags match GestureDirection.allCases index: up=0, down=1, left=2, right=3
    // Scroll popup tags: scrollUp=10, scrollDown=11

    private static let tagForDirection: [GestureDirection: Int] = {
        var map: [GestureDirection: Int] = [:]
        for (index, direction) in GestureDirection.allCases.enumerated() {
            map[direction] = index
        }
        return map
    }()

    private static let scrollTagUp   = 10
    private static let scrollTagDown = 11

    private func direction(forMovementTag tag: Int) -> GestureDirection? {
        return GestureDirection.allCases.indices.contains(tag)
            ? GestureDirection.allCases[tag]
            : nil
    }

    private func movementPopUp(for direction: GestureDirection) -> NSPopUpButton {
        switch direction {
        case .up:    return upPopUp
        case .down:  return downPopUp
        case .left:  return leftPopUp
        case .right: return rightPopUp
        }
    }

    private func scrollPopUp(for direction: GestureDirection) -> NSPopUpButton? {
        switch direction {
        case .up:   return scrollUpPopUp
        case .down: return scrollDownPopUp
        default:    return nil
        }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("GestureTableCellView must be created programmatically")
    }

    // MARK: - Layout

    private func setupLayout() {
        // Right-click context menu for deletion
        let contextMenu = NSMenu()
        let deleteItem = NSMenuItem(
            title: NSLocalizedString("delete", comment: ""),
            action: #selector(deleteGesture(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        contextMenu.addItem(deleteItem)
        self.menu = contextMenu

        // --- KeyPreview ---
        keyPreview = KeyPreview()
        keyPreview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyPreview)

        // --- Movement section ---
        let movementSection = makeSectionView(
            title: NSLocalizedString("gestureMovement", comment: ""),
            content: makeMovementStack()
        )
        movementSection.translatesAutoresizingMaskIntoConstraints = false
        addSubview(movementSection)

        // --- Scroll section ---
        let scrollSection = makeSectionView(
            title: NSLocalizedString("gestureScroll", comment: ""),
            content: makeScrollStack()
        )
        scrollSection.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollSection)

        // --- Auto Layout ---
        NSLayoutConstraint.activate([
            // KeyPreview: left-anchored, vertically centered
            keyPreview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            keyPreview.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Movement section: right of keyPreview, vertically centered
            movementSection.leadingAnchor.constraint(equalTo: centerXAnchor, constant: -120),
            movementSection.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Scroll section: right of movement section, vertically centered
            scrollSection.leadingAnchor.constraint(equalTo: movementSection.trailingAnchor, constant: 16),
            scrollSection.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            scrollSection.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Wraps a title label + content view into a labeled section container.
    private func makeSectionView(title: String, content: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            content.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// Vertical stack of 4 movement direction rows (↑↓←→ in visual order: up, left, right, down).
    private func makeMovementStack() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        let visualOrder: [GestureDirection] = [.up, .left, .right, .down]
        for direction in visualOrder {
            stack.addArrangedSubview(makeMovementRow(for: direction))
        }
        return stack
    }

    /// Vertical stack of 2 scroll direction rows (↑↓).
    private func makeScrollStack() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        for direction in [GestureDirection.up, .down] {
            stack.addArrangedSubview(makeScrollRow(for: direction))
        }
        return stack
    }

    /// Single horizontal row for a movement direction: [arrow label] [popup]
    private func makeMovementRow(for direction: GestureDirection) -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.tag = GestureTableCellView.tagForDirection[direction] ?? 0
        popup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        switch direction {
        case .up:    upPopUp    = popup
        case .down:  downPopUp  = popup
        case .left:  leftPopUp  = popup
        case .right: rightPopUp = popup
        }

        return makeDirectionRow(arrowSymbol: direction.arrowSymbol, popup: popup)
    }

    /// Single horizontal row for a scroll direction: [arrow label] [popup]
    private func makeScrollRow(for direction: GestureDirection) -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.tag = direction == .up ? GestureTableCellView.scrollTagUp
                                     : GestureTableCellView.scrollTagDown
        popup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        switch direction {
        case .up:   scrollUpPopUp   = popup
        case .down: scrollDownPopUp = popup
        default:    break
        }

        return makeDirectionRow(arrowSymbol: direction.arrowSymbol, popup: popup)
    }

    /// Generic [arrow label] [popup] row.
    private func makeDirectionRow(arrowSymbol: String, popup: NSPopUpButton) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: arrowSymbol)
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(popup)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.widthAnchor.constraint(equalToConstant: 20),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            popup.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            popup.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            row.heightAnchor.constraint(equalTo: popup.heightAnchor),
        ])
        return row
    }

    // MARK: - Configure

    func configure(
        with binding: GestureBinding,
        onMovementActionChanged: @escaping (GestureDirection, SystemShortcut.Shortcut?) -> Void,
        onScrollActionChanged: @escaping (GestureDirection, SystemShortcut.Shortcut?) -> Void,
        onDeleteRequested: @escaping () -> Void
    ) {
        self.onMovementActionChanged = onMovementActionChanged
        self.onScrollActionChanged   = onScrollActionChanged
        self.onDeleteRequested       = onDeleteRequested

        // Update movement state cache
        currentActions[.up]    = binding.upAction
        currentActions[.down]  = binding.downAction
        currentActions[.left]  = binding.leftAction
        currentActions[.right] = binding.rightAction

        // Update scroll state cache
        currentScrollActions[.up]   = binding.scrollUpAction
        currentScrollActions[.down] = binding.scrollDownAction

        // KeyPreview
        keyPreview.update(from: binding.triggerEvent.displayComponents, status: .normal)

        // Build movement menus
        for direction in GestureDirection.allCases {
            setupMovementPopUp(movementPopUp(for: direction), direction: direction, actionName: binding.action(for: direction))
        }

        // Build scroll menus
        for direction in [GestureDirection.up, .down] {
            if let popup = scrollPopUp(for: direction) {
                setupScrollPopUp(popup, direction: direction, actionName: binding.scrollAction(for: direction))
            }
        }
    }

    // MARK: - PopUp Setup

    private func setupMovementPopUp(_ popup: NSPopUpButton, direction: GestureDirection, actionName: String?) {
        let menu = NSMenu()
        menu.delegate = self
        ShortcutManager.buildShortcutMenu(into: menu, target: self, action: #selector(movementShortcutSelected(_:)), showLogiActions: false)
        disableKeyEquivalents(in: menu)
        popup.menu = menu
        refreshDisplay(for: popup, actionName: actionName)
    }

    private func setupScrollPopUp(_ popup: NSPopUpButton, direction: GestureDirection, actionName: String?) {
        let menu = NSMenu()
        menu.delegate = self
        ShortcutManager.buildShortcutMenu(into: menu, target: self, action: #selector(scrollShortcutSelected(_:)), showLogiActions: false)
        disableKeyEquivalents(in: menu)
        popup.menu = menu
        refreshDisplay(for: popup, actionName: actionName)
    }

    /// Updates the placeholder item (index 0) of the popup to show the current action.
    private func refreshDisplay(for popup: NSPopUpButton, actionName: String?) {
        guard let menu = popup.menu,
              let placeholderItem = menu.items.first else { return }

        if let name = actionName, let shortcut = SystemShortcut.getShortcut(named: name) {
            placeholderItem.title = shortcut.localizedName
        } else {
            placeholderItem.title = NSLocalizedString("gestureNone", comment: "")
        }
        placeholderItem.image = nil
        popup.selectItem(at: 0)
        popup.synchronizeTitleAndSelectedItem()
    }

    // MARK: - Actions

    @objc private func movementShortcutSelected(_ sender: NSMenuItem) {
        guard let popup = findPopUpInMovement(containing: sender),
              let direction = direction(forMovementTag: popup.tag) else { return }

        if sender.representedObject as? String == "__custom__" { return }

        let shortcut = sender.representedObject as? SystemShortcut.Shortcut
        currentActions[direction] = shortcut?.identifier
        refreshDisplay(for: popup, actionName: shortcut?.identifier)
        onMovementActionChanged?(direction, shortcut)
    }

    @objc private func scrollShortcutSelected(_ sender: NSMenuItem) {
        guard let popup = findPopUpInScroll(containing: sender) else { return }

        if sender.representedObject as? String == "__custom__" { return }

        let direction: GestureDirection = popup === scrollUpPopUp ? .up : .down
        let shortcut = sender.representedObject as? SystemShortcut.Shortcut
        currentScrollActions[direction] = shortcut?.identifier
        refreshDisplay(for: popup, actionName: shortcut?.identifier)
        onScrollActionChanged?(direction, shortcut)
    }

    @objc private func deleteGesture(_ sender: NSMenuItem) {
        onDeleteRequested?()
    }

    // MARK: - PopUp Lookup

    private func findPopUpInMovement(containing item: NSMenuItem) -> NSPopUpButton? {
        let allPopUps: [NSPopUpButton] = [upPopUp, downPopUp, leftPopUp, rightPopUp]
        return allPopUps.first { menuContains($0.menu, item: item) }
    }

    private func findPopUpInScroll(containing item: NSMenuItem) -> NSPopUpButton? {
        return [scrollUpPopUp, scrollDownPopUp].first { menuContains($0?.menu, item: item) } ?? nil
    }

    private func menuContains(_ menu: NSMenu?, item: NSMenuItem) -> Bool {
        guard let menu = menu else { return false }
        for menuItem in menu.items {
            if menuItem === item { return true }
            if let sub = menuItem.submenu, menuContains(sub, item: item) { return true }
        }
        return false
    }
}

// MARK: - NSMenuDelegate

extension GestureTableCellView {

    func menuWillOpen(_ menu: NSMenu) {
        adjustMenuStructure(menu)
        enableKeyEquivalents(in: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        disableKeyEquivalents(in: menu)
    }

    /// Dynamically adjusts placeholder / unbound item visibility.
    private func adjustMenuStructure(_ menu: NSMenu) {
        guard menu.items.count >= 3 else { return }

        // Determine current action name for this menu
        let currentActionName: String??

        if let ownerPopup = [upPopUp, downPopUp, leftPopUp, rightPopUp]
                .first(where: { $0.menu === menu }),
           let direction = direction(forMovementTag: ownerPopup.tag) {
            currentActionName = currentActions[direction]
        } else if let ownerPopup = [scrollUpPopUp, scrollDownPopUp]
                .first(where: { $0?.menu === menu }) {
            let direction: GestureDirection = ownerPopup === scrollUpPopUp ? .up : .down
            currentActionName = currentScrollActions[direction]
        } else {
            return
        }

        let placeholderItem = menu.items[0]
        let firstSeparator  = menu.items[1]
        let unboundItem     = menu.items[2]

        let hasBoundAction = (currentActionName ?? nil) != nil

        if hasBoundAction {
            placeholderItem.isHidden = false
            firstSeparator.isHidden  = false
            unboundItem.title        = NSLocalizedString("unbind", comment: "")
        } else {
            placeholderItem.isHidden = true
            firstSeparator.isHidden  = true
            unboundItem.title        = NSLocalizedString("unbound", comment: "")
        }
    }

    private func enableKeyEquivalents(in menu: NSMenu) {
        for item in menu.items {
            if let shortcut = item.representedObject as? SystemShortcut.Shortcut {
                let keyEquivalent = shortcut.keyEquivalent
                item.keyEquivalent            = keyEquivalent.keyEquivalent
                item.keyEquivalentModifierMask = keyEquivalent.modifierMask
            }
            if let submenu = item.submenu { enableKeyEquivalents(in: submenu) }
        }
    }

    private func disableKeyEquivalents(in menu: NSMenu) {
        for item in menu.items {
            item.keyEquivalent            = ""
            item.keyEquivalentModifierMask = []
            if let submenu = item.submenu { disableKeyEquivalents(in: submenu) }
        }
    }
}
