# Mos Mouse Scroll Action Design

## Overview

Add a Mos-owned "Mouse Scroll" action group to the Buttons preferences action menu. The group appears below "Mouse Buttons" and exposes the same three scroll function roles as the Scrolling preferences panel: dash, toggle, and block.

The feature lets users bind multiple physical buttons, including Logi HID++ buttons, to the same scroll role without changing the existing single-key persisted Scrolling preferences format.

## Goals

- Add a `[Mos] Mouse Scroll` action group below the mouse-button action group.
- Render `[Mos]` with a reusable tag renderer using the Mos logo-inspired blue/purple gradient and subtle inner highlight.
- Keep Logi tag rendering on the same shared path.
- Support three Mos scroll actions: dash, toggle, and block.
- Make the new actions stateful: down activates the role, up releases it.
- Allow multiple button bindings to activate the same scroll role at the same time without premature release.
- Preserve all existing `dash`, `toggle`, and `block` persistence compatibility for old users.
- Keep Logi button support through the existing ButtonCore and Logi bridge paths.

## Non-Goals

- Do not migrate Scrolling preferences from `ScrollHotkey?` to arrays in this change.
- Do not redesign the Scrolling preferences UI.
- Do not change existing Logi feature actions.
- Do not make Mos scroll actions conditional on the trigger being Logi.
- Do not change `RecordedEvent.displayComponents` storage shape.

## Current Architecture

The Buttons preferences action menu is built by `ShortcutManager.buildShortcutMenu(...)`, with shortcut definitions and categories in `SystemShortcut`. `ButtonTableCellView` configures the popup and uses `ActionDisplayResolver` plus `ActionDisplayRenderer` for selected-action presentation.

Button execution flows through `InputProcessor`, which resolves a `ButtonBinding` into `ResolvedAction` and stores stateful actions in `activeBindings` until the matching up event arrives.

Scroll hotkeys currently use `OPTIONS_SCROLL_DEFAULT.dash`, `.toggle`, and `.block`, each as one `ScrollHotkey?`. `ScrollCore` also tracks one held state per role. That model stays intact for existing Scrolling preferences and is supplemented by a new button-action activation source.

Logi HID++ button events already enter the same ButtonCore pipeline through `LogiIntegrationBridge.dispatchLogiButtonEvent(...)`. Logi usage/divert registration for button bindings already registers enabled mouse trigger codes, so a Logi trigger bound to a Mos scroll action is covered by the existing path.

## Design

### 1. Reuse and generalize tag rendering

Keep the existing `BrandTag` rendering utility but make its model semantically reusable for Mos tags:

- Add `BrandTagConfig.mos`.
- Let action presentation carry a generic `tag` instead of Logi-specific brand semantics.
- Keep `BrandTag.createTagImage(...)`, `createTagView(...)`, and `createPrefixedImage(...)` as the shared rendering functions.

The final Mos tag style is:

- text: `Mos`
- background: dark blue to purple gradient
- foreground: near-white
- accent: low-opacity inner highlight, without the earlier bright outer border

This keeps the current Logi tag output stable while giving future tags one public rendering path.

### 2. Add Mos scroll action definitions

Add three predefined action identifiers:

- `mosScrollDash`
- `mosScrollToggle`
- `mosScrollBlock`

Group them under a new category:

- `categoryMosMouseScroll`

The category should be inserted after `SystemShortcut.mouseButtonsCategory` and before the conditional Logi category in `ShortcutManager`.

The category menu item uses the Mos tag image and localized title "Mouse Scroll". The submenu contains the three role actions.

### 3. Add stateful Mos scroll execution

Add a `ResolvedAction.mosScroll(role: ScrollRole)` case. It is stateful, like mouse-button and custom-key actions.

`ShortcutExecutor.resolveAction(...)` maps the three `mosScroll*` identifiers to the corresponding `ScrollRole`. `ShortcutExecutor.execute(...)` forwards down/up to a ScrollCore API dedicated to button-driven scroll actions.

### 4. Extend ScrollCore with button-action activation sources

Add per-role active counts for Mos scroll actions. A down event increments the count, and an up event decrements it. The role stays active while its count is above zero.

ScrollCore then derives the final role state from all active sources:

- existing configured hotkey state
- existing HID++ configured hotkey state
- new Mos button-action active count

For dash, the amplification is `5.0` while any dash source is active and `1.0` otherwise.

This is the important safety rule: if two buttons are both bound to `mosScrollDash`, pressing both and releasing one keeps dash active until the second is released.

### 5. Preserve old persistence

The existing Scrolling preferences fields stay as:

- `dash: ScrollHotkey?`
- `toggle: ScrollHotkey?`
- `block: ScrollHotkey?`

The new multi-binding behavior comes from multiple `ButtonBinding` records pointing to the same Mos scroll action identifier. No old UserDefaults or app-level scroll configuration needs migration.

## Testing

Focused tests should cover:

- Mos tag configuration and action display tag resolution.
- Shortcut menu order: mouse buttons, Mos mouse scroll, then Logi actions when available.
- `mosScrollDash` resolves to a stateful Mos scroll action.
- Button down/up activates and releases each scroll role.
- Two trigger buttons bound to the same scroll role do not prematurely release the role.
- Logi trigger bindings continue through the same stateful action path.

Verification should run focused tests first, then the full Debug test plan when the implementation is stable.
