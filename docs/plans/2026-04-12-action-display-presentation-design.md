# Unified Action Display Presentation Design

## Overview

Unify the final Action button presentation in the Buttons preferences UI through a single semantic resolver and a single renderer. The goal is to stop scattering display rules across `ButtonTableCellView`, and instead make every binding state flow through one presentation pipeline.

This design focuses only on UI presentation. It does not change button-mapping behavior, matching, or execution.

## Problem Statement

The current Action button display is functionally correct in many cases, but its logic is split across multiple paths:

- predefined shortcuts are displayed by copying menu item title and image
- custom bindings use badge rendering from `displayComponents`
- some custom bindings are upgraded to named actions via `SystemShortcut.displayShortcut(matchingBindingName:)`
- brand styling is applied only in some branches through `BrandTag.brandForAction(...)`
- recording state and unbound state are handled directly inside `ButtonTableCellView`

This creates inconsistent output for semantically equivalent actions. The clearest current example is Logi actions:

- manually selected Logi actions render as `ActionName + Logi tag`
- custom-recorded Logi actions fall back to generic badges like `Forward Button + [Logi]`

The same structural issue already showed up in:

- recording prompt vs unbound fallback
- custom combos that should display as named shortcuts
- brand-tag placement and styling

If we keep extending `ButtonTableCellView` with more branch-specific fixes, future display logic will continue to drift.

## Goals

- Provide one final presentation pipeline for every Action button state
- Keep semantic resolution separate from AppKit rendering
- Ensure equivalent actions render equivalently regardless of how they were chosen
- Preserve current good behavior for unbound, recording, named actions, custom key combos, and brand actions
- Make brand tags first-class presentation data rather than ad-hoc text badges
- Make future additions require changes in one place instead of several view-specific branches

## Non-Goals

- No changes to button matching or execution behavior
- No redesign of the existing menu hierarchy
- No multi-brand system beyond current needs
- No replacement of `SystemShortcut` as the source of shortcut metadata

## Current Constraints

The current view already has several useful building blocks:

- `SystemShortcut.displayShortcut(matchingBindingName:)` can recognize some custom bindings as named shortcuts
- `BrandTag.brandForAction(_:)` and `BrandTag.brandForCode(_:)` already encode Logi brand knowledge
- `createBadgeImage(from:)` already provides a compact fallback renderer for generic custom combos
- `ButtonTableCellView` already knows about transient UI states like recording

The problem is not missing data. The problem is that each branch decides its own presentation.

## Recommended Architecture

### 1. Add `ActionDisplayResolver`

Create a small resolver responsible for translating current binding state into a semantic presentation model.

Its inputs should be view-facing state only:

- current predefined shortcut, if any
- current custom binding name, if any
- whether recording is active

Its output should be a single `ActionPresentation` value.

### 2. Add `ActionDisplayRenderer`

Create a renderer responsible for turning `ActionPresentation` into the final `NSPopUpButton` placeholder content.

The renderer should be the only place that:

- sets placeholder title
- sets placeholder image
- prefixes brand tags to images
- chooses badge image rendering for key combos
- synchronizes the popup button title and selection state

### 3. Keep business lookup outside the view

`ButtonTableCellView` should stop deciding whether a binding is:

- named
- custom
- branded
- generic badge-only

Instead it should do only:

1. gather current local state
2. ask the resolver for an `ActionPresentation`
3. ask the renderer to apply that presentation

This keeps the table cell thin and predictable.

## Presentation Model

Use a compact semantic model instead of directly passing raw strings around.

```swift
struct ActionPresentation {
    let kind: ActionPresentationKind
    let title: String
    let image: NSImage?
    let badgeComponents: [String]
    let brand: BrandTagConfig?
}

enum ActionPresentationKind {
    case unbound
    case recordingPrompt
    case namedAction
    case keyCombo
}
```

This is intentionally small:

- `title` covers unbound, prompt, and named actions
- `image` covers menu-backed named actions
- `badgeComponents` covers generic keyboard-style combos
- `brand` makes Logi-style brand rendering first-class

If we later need richer presentation, we can extend the model without re-splitting the logic.

## Resolution Rules

The resolver should follow a strict priority order.

### 1. Recording prompt wins

If recording is active, return:

- `kind: .recordingPrompt`
- localized short prompt text
- no image
- no badges
- no brand

This prevents temporary fallback to unbound or stale content while the recorder is active.

### 2. Predefined shortcut wins next

If `currentShortcut` exists, resolve to:

- `kind: .namedAction`
- title from the shortcut
- image from the shortcut/menu metadata
- brand from `BrandTag.brandForAction(shortcut.identifier)`

This preserves current menu-driven predefined action display.

### 3. Recognizable custom binding upgrades to named action

If `currentCustomName` exists and maps uniquely to a predefined shortcut through `SystemShortcut.displayShortcut(matchingBindingName:)`, resolve it exactly like a predefined shortcut.

This ensures:

- `custom::⌘⇧4` displays as `截取所选区域`
- a custom-recorded Logi button that maps to a known Logi action displays as `Forward Button + Logi tag`

The crucial rule is semantic equivalence:

- if the binding meaning is recognized uniquely, the display must match the predefined action display

### 4. Generic custom binding falls back to key combo

If the custom binding does not map uniquely to a named action:

- parse it into normalized components
- resolve its visible badge components
- derive brand from code when appropriate, such as raw Logi codes

This enables a better fallback for cases like:

- keyboard combo only
- modifier combo plus a raw device button
- raw Logi button that is not otherwise upgraded

For branded generic combos, the primary action name and the brand tag should still be separated semantically. The brand should not be represented as a gray text badge.

### 5. Unbound is the final fallback

If none of the above apply, return:

- `kind: .unbound`
- localized unbound text

## Rendering Rules

The renderer should make equivalent semantic presentations look equivalent, regardless of source.

### Named actions

Named actions render as:

- title text
- optional icon
- optional prefixed brand tag image if `brand` exists

This should reuse the existing visual style used by predefined menu items.

### Generic key combos

Generic combos render as:

- badge image from the normalized components
- optional prefixed brand tag if the action carries a brand

For example:

- keyboard-only combo: keyboard icon + modifier/key badges
- modifier + Logi action fallback: modifier badges + primary action badge, with Logi tag rendered as a real tag rather than `[Logi]`

If the renderer cannot gracefully prefix a brand tag to the badge image, it may render the brand tag as part of a dedicated composite image. The important rule is still that brands are styled brands, not plain text badges.

### Recording prompt

Recording prompt renders as:

- short localized title
- no icon
- no badge image

### Unbound

Unbound renders as:

- localized `unbound`
- no icon

## Migration Strategy

### Move out of `ButtonTableCellView`

These responsibilities should move into the resolver:

- `resolvedDisplayShortcut()`
- choosing between current shortcut vs current custom name
- choosing named action vs custom badge vs unbound
- identifying brand information for final presentation

These responsibilities should move into the renderer:

- `setCustomTitle(...)`
- image prefixing for brands
- badge image application
- popup placeholder synchronization

`ButtonTableCellView` should retain only:

- state fields
- menu interactions
- recorder lifecycle
- `refreshActionDisplay()`

### Preserve menu construction

`ShortcutManager.buildShortcutMenu(...)` should remain unchanged in this iteration. The menu remains the source for selectable actions. The new presentation system only changes how the chosen action is shown afterwards.

## Testing Strategy

Add tests at the semantic layer first, then light view-layer verification.

### Resolver tests

Add dedicated tests for:

- recording prompt beats all other states
- predefined shortcut resolves to named action
- recognizable custom shortcut resolves to the same named action
- custom Logi binding resolves to branded named action when uniquely recognized
- generic custom keyboard combo resolves to key-combo presentation
- raw unbound state resolves to unbound presentation

### Renderer tests

Keep rendering tests lightweight and focused on output decisions:

- named action with brand prefixes brand tag
- key combo renders badge image
- prompt and unbound do not attach stale icons or tags

### Integration tests

Update button binding UI tests to verify that:

- manually selected Logi actions and custom-recorded equivalent Logi actions render consistently
- `custom::⌘⇧4` displays as the named screenshot action
- recording prompt transitions correctly back to resolved content

## Benefits

This design gives us:

- one place to reason about action display semantics
- one place to reason about final rendering behavior
- consistency across manual selection and custom recording paths
- cleaner future extension for brands, aliases, and named-action upgrades
- less repeated UI glue in `ButtonTableCellView`

## Recommended Next Step

Implement the resolver and renderer in small steps:

1. add tests for current inconsistent cases
2. introduce `ActionPresentation` and `ActionDisplayResolver`
3. introduce `ActionDisplayRenderer`
4. migrate `ButtonTableCellView.refreshActionDisplay()` to the new pipeline
5. remove the old branch-specific display helpers once parity is confirmed
