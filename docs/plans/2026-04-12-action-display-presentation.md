# Unified Action Display Presentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the scattered Action button display logic with a unified semantic presentation pipeline so predefined actions, custom bindings, Logi-branded actions, recording prompts, and unbound state all render consistently.

**Architecture:** Introduce `ActionPresentation`, `ActionDisplayResolver`, and `ActionDisplayRenderer`. Keep `ButtonTableCellView` responsible only for local state and interaction, while resolution and rendering move into dedicated helpers.

**Tech Stack:** Swift, AppKit `NSPopUpButton`, existing `SystemShortcut`, `BrandTag`, `ButtonTableCellView`, and `xcodebuild test`

---

### Task 1: Add failing tests for current presentation inconsistencies

**Files:**
- Modify: `MosTests/ButtonBindingTests.swift`

**Step 1: Add resolver-focused expectations in existing tests or lightweight presentation helpers**

Cover at least:

- recording prompt takes precedence over unbound/custom/named content
- `custom::⌘⇧4` resolves to the same display title as the predefined screenshot action
- custom-recorded Logi actions resolve to branded display semantics instead of raw `[Logi]` text badges
- generic custom combos still fall back to badge-style presentation

**Step 2: Run focused tests and confirm they fail before implementation**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: failures around missing unified presentation behavior.

**Step 3: Commit nothing yet**

Do not commit in red state.

### Task 2: Introduce `ActionPresentation` and `ActionDisplayResolver`

**Files:**
- Create: `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift`
- Modify: `Mos/Shortcut/SystemShortcut.swift`
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift`
- Test: `MosTests/ButtonBindingTests.swift`

**Step 1: Define the presentation model**

Add:

```swift
struct ActionPresentation { ... }
enum ActionPresentationKind { ... }
```

Keep it small and semantic.

**Step 2: Implement resolver entry points**

Add a resolver API shaped roughly like:

```swift
func resolve(
    shortcut: SystemShortcut.Shortcut?,
    customBindingName: String?,
    isRecording: Bool
) -> ActionPresentation
```

**Step 3: Move semantic decisions into the resolver**

Resolver should decide:

- prompt vs shortcut vs recognized custom vs generic custom vs unbound
- named action upgrade through `SystemShortcut.displayShortcut(matchingBindingName:)`
- brand derivation through identifier or code
- normalized badge components for fallback custom bindings

**Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: semantic-resolution tests pass.

**Step 5: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift Mos/Shortcut/SystemShortcut.swift Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift MosTests/ButtonBindingTests.swift
git commit -m "refactor(buttons): resolve action display semantics centrally"
```

### Task 3: Introduce `ActionDisplayRenderer`

**Files:**
- Create: `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayRenderer.swift`
- Modify: `Mos/Components/BrandTag.swift`
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift`
- Test: `MosTests/ButtonBindingTests.swift`

**Step 1: Move placeholder rendering responsibilities out of the cell**

Create a renderer API shaped roughly like:

```swift
func render(
    _ presentation: ActionPresentation,
    into popupButton: NSPopUpButton
)
```

**Step 2: Centralize final visual output**

Renderer should handle:

- placeholder title
- placeholder image
- popup selected item/title synchronization
- brand prefix rendering
- key-combo badge rendering

**Step 3: Keep cell-specific drawing helpers only if still useful**

If badge image generation stays in the cell today, move it behind the renderer so the cell no longer decides when to use it.

**Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: renderer-backed display tests pass.

**Step 5: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayRenderer.swift Mos/Components/BrandTag.swift Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift MosTests/ButtonBindingTests.swift
git commit -m "refactor(buttons): centralize action display rendering"
```

### Task 4: Migrate `ButtonTableCellView` to the new pipeline

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift`
- Test: `MosTests/ButtonBindingTests.swift`

**Step 1: Replace branch-specific refresh logic**

Change `refreshActionDisplay()` to:

1. build presentation through the resolver
2. render via the renderer

**Step 2: Remove or inline obsolete helpers**

Delete or stop using logic that is now duplicated by the resolver/renderer:

- `resolvedDisplayShortcut()`
- `displayCustomBinding(_:)`
- direct brand-tag branching in `setCustomTitle(...)`

Keep only the minimal helpers that are still view plumbing.

**Step 3: Validate recording transitions**

Ensure:

- entering recording shows prompt immediately
- cancel/timeout returns to the correct resolved state
- successful recording upgrades to a named action when applicable

**Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: presentation flow is green end-to-end.

**Step 5: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift MosTests/ButtonBindingTests.swift
git commit -m "refactor(buttons): route action display through presenter pipeline"
```

### Task 5: Run full verification and clean up

**Files:**
- Modify only if needed based on test failures

**Step 1: Run full suite**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

**Step 2: Verify key UI outcomes manually**

Sanity-check these UI states:

- unbound
- recording prompt
- predefined action
- custom combo fallback
- custom combo upgraded to named screenshot action
- predefined Logi action
- custom-recorded Logi action that should render identically to predefined Logi action

**Step 3: Commit any final fixups**

If verification requires small fixups, commit them separately with a focused message.

### Task 6: Decide how to continue

After implementation and verification:

1. continue in the same session and implement from this plan, or
2. open a new execution session dedicated to the presenter refactor

Do not skip verification before claiming success.
