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
    private var upPopUp: NSPopUpButton!
    private var downPopUp: NSPopUpButton!
    private var leftPopUp: NSPopUpButton!
    private var rightPopUp: NSPopUpButton!

    // MARK: - State

    /// Per-direction current action identifier (nil = unbound)
    private var currentActions: [GestureDirection: String?] = [
        .up: nil, .down: nil, .left: nil, .right: nil,
    ]

    // MARK: - Callbacks

    private var onDirectionActionChanged: ((GestureDirection, SystemShortcut.Shortcut?) -> Void)?
    private var onDeleteRequested: (() -> Void)?

    // MARK: - Tags
    // Tag values match GestureDirection.allCases index: up=0, down=1, left=2, right=3

    private static let tagForDirection: [GestureDirection: Int] = {
        var map: [GestureDirection: Int] = [:]
        for (index, direction) in GestureDirection.allCases.enumerated() {
            map[direction] = index
        }
        return map
    }()

    private func direction(forTag tag: Int) -> GestureDirection? {
        return GestureDirection.allCases.indices.contains(tag)
            ? GestureDirection.allCases[tag]
            : nil
    }

    private func popUp(for direction: GestureDirection) -> NSPopUpButton {
        switch direction {
        case .up:    return upPopUp
        case .down:  return downPopUp
        case .left:  return leftPopUp
        case .right: return rightPopUp
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
        // --- KeyPreview ---
        keyPreview = KeyPreview()
        keyPreview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyPreview)

        // --- Direction rows (visual order: up, left, right, down) ---
        let directionStack = NSStackView()
        directionStack.orientation = .vertical
        directionStack.alignment = .leading
        directionStack.spacing = 4
        directionStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(directionStack)

        let visualOrder: [GestureDirection] = [.up, .left, .right, .down]
        for direction in visualOrder {
            let row = makeDirectionRow(for: direction)
            directionStack.addArrangedSubview(row)
        }

        // --- Auto Layout ---
        NSLayoutConstraint.activate([
            // KeyPreview: left-anchored, vertically centered
            keyPreview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            keyPreview.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Direction stack: to the right of center (generous left margin),
            // vertically centered
            directionStack.leadingAnchor.constraint(equalTo: centerXAnchor, constant: -20),
            directionStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            directionStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Creates a single horizontal row: [arrow label] [popup button]
    private func makeDirectionRow(for direction: GestureDirection) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        // Arrow label
        let label = NSTextField(labelWithString: direction.arrowSymbol)
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        // PopUpButton
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.tag = GestureTableCellView.tagForDirection[direction] ?? 0
        row.addSubview(popup)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.widthAnchor.constraint(equalToConstant: 20),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            popup.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            popup.widthAnchor.constraint(equalToConstant: 200),
            popup.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            row.heightAnchor.constraint(equalTo: popup.heightAnchor),
        ])

        // Store reference
        switch direction {
        case .up:    upPopUp    = popup
        case .down:  downPopUp  = popup
        case .left:  leftPopUp  = popup
        case .right: rightPopUp = popup
        }

        return row
    }

    // MARK: - Configure

    func configure(
        with binding: GestureBinding,
        onDirectionActionChanged: @escaping (GestureDirection, SystemShortcut.Shortcut?) -> Void,
        onDeleteRequested: @escaping () -> Void
    ) {
        self.onDirectionActionChanged = onDirectionActionChanged
        self.onDeleteRequested = onDeleteRequested

        // Update state cache
        currentActions[.up]    = binding.upAction
        currentActions[.down]  = binding.downAction
        currentActions[.left]  = binding.leftAction
        currentActions[.right] = binding.rightAction

        // KeyPreview
        keyPreview.update(from: binding.triggerEvent.displayComponents, status: .normal)

        // Build menus for each direction
        for direction in GestureDirection.allCases {
            setupPopUp(popUp(for: direction), direction: direction, actionName: binding.action(for: direction))
        }
    }

    // MARK: - PopUp Setup

    private func setupPopUp(_ popup: NSPopUpButton, direction: GestureDirection, actionName: String?) {
        let menu = NSMenu()
        menu.delegate = self

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: self,
            action: #selector(shortcutSelected(_:)),
            showLogiActions: false
        )

        disableKeyEquivalents(in: menu)

        popup.menu = menu

        // Reflect current action in the placeholder slot (index 0)
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

    @objc private func shortcutSelected(_ sender: NSMenuItem) {
        // Identify which direction this popup belongs to via the popup's tag
        guard let popup = findPopUp(containing: sender),
              let direction = direction(forTag: popup.tag) else { return }

        // Ignore custom shortcut option — gestures don't support custom key combos
        if sender.representedObject as? String == "__custom__" {
            return
        }

        let shortcut = sender.representedObject as? SystemShortcut.Shortcut

        // Update local state
        currentActions[direction] = shortcut?.identifier

        // Update placeholder display
        refreshDisplay(for: popup, actionName: shortcut?.identifier)

        // Notify caller
        onDirectionActionChanged?(direction, shortcut)
    }

    /// Walks through the sender's menu hierarchy to find which of our popups owns it.
    private func findPopUp(containing item: NSMenuItem) -> NSPopUpButton? {
        let allPopUps: [NSPopUpButton] = [upPopUp, downPopUp, leftPopUp, rightPopUp]
        for popup in allPopUps {
            if menuContains(popup.menu, item: item) {
                return popup
            }
        }
        return nil
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

    /// Dynamically adjusts placeholder / unbound item visibility based on current binding state.
    private func adjustMenuStructure(_ menu: NSMenu) {
        guard menu.items.count >= 3 else { return }

        // Determine which direction owns this menu
        let allPopUps: [NSPopUpButton] = [upPopUp, downPopUp, leftPopUp, rightPopUp]
        guard let ownerPopup = allPopUps.first(where: { $0.menu === menu }),
              let direction = direction(forTag: ownerPopup.tag) else { return }

        let placeholderItem = menu.items[0]
        let firstSeparator  = menu.items[1]
        let unboundItem     = menu.items[2]

        let currentActionName = currentActions[direction] ?? nil
        let hasBoundAction = currentActionName != nil

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

    /// Recursively enables key equivalents from representedObject.
    private func enableKeyEquivalents(in menu: NSMenu) {
        for item in menu.items {
            if let shortcut = item.representedObject as? SystemShortcut.Shortcut {
                let keyEquivalent = shortcut.keyEquivalent
                item.keyEquivalent                 = keyEquivalent.keyEquivalent
                item.keyEquivalentModifierMask      = keyEquivalent.modifierMask
            }
            if let submenu = item.submenu {
                enableKeyEquivalents(in: submenu)
            }
        }
    }

    /// Recursively disables all key equivalents.
    private func disableKeyEquivalents(in menu: NSMenu) {
        for item in menu.items {
            item.keyEquivalent            = ""
            item.keyEquivalentModifierMask = []
            if let submenu = item.submenu {
                disableKeyEquivalents(in: submenu)
            }
        }
    }
}
