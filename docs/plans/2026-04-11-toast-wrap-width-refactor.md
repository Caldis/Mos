# Toast Wrap Width Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove `expandMessage` and the old full-text default setting, replace them with a single `wrapWidth` API, and make the default toast layout single-line unless a positive wrap width is explicitly provided.

**Architecture:** Thread a `wrapWidth` value from `Toast.show(...)` through `ToastManager` into `ToastContentView`, where `nil` or non-positive values mean single-line truncation and positive values mean word-wrapped multiline layout. Remove the `showsFullText` storage/UI path so there is only one text-layout control model left in the component.

**Tech Stack:** Swift, AppKit, `UserDefaults`, existing toast regression harness in `tools/regression/toast-regression-tests.swift`

---

### Task 1: Write failing regression tests for wrap-width semantics

**Files:**
- Modify: `tools/regression/toast-regression-tests.swift`

**Step 1: Write the failing test**

Add regression tests asserting:
- `ToastContentView` defaults to single-line truncation when no wrap width is provided
- `wrapWidth: 0` also forces single-line truncation
- positive `wrapWidth` enables multiline wrapping and uses that width for layout
- multiline mode does not collapse to icon-only width

**Step 2: Run test to verify it fails**

Run: `swiftc -module-cache-path /tmp/mos-toast-tests-cache -o /tmp/mos-toast-tests-bin tools/regression/toast-regression-tests.swift Mos/Components/Toast/ToastLayout.swift Mos/Components/Toast/ToastVisibilityRules.swift Mos/Components/Toast/ToastContentView.swift Mos/Components/Toast/ToastStorage.swift && /tmp/mos-toast-tests-bin`

Expected: FAIL because `ToastContentView` still uses `expandMessage` semantics and default multiline storage assumptions.

### Task 2: Replace `expandMessage` with `wrapWidth`

**Files:**
- Modify: `Mos/Components/Toast/Toast.swift`
- Modify: `Mos/Components/Toast/ToastManager.swift`
- Modify: `Mos/Components/Toast/ToastContentView.swift`
- Modify: `Mos/AppDelegate.swift`

**Step 1: Write minimal implementation**

Replace `expandMessage` with `wrapWidth: CGFloat?`. Interpret `nil` or `<= 0` as single-line truncation, and positive values as multiline wrapping with `preferredMaxLayoutWidth = wrapWidth`. Update all call sites, including any current `expandMessage: true` usage.

**Step 2: Run test to verify it passes**

Run the same regression command as Task 1.

Expected: PASS for the new single-line default and positive-wrap-width behaviors.

### Task 3: Remove obsolete full-text preference plumbing

**Files:**
- Modify: `Mos/Components/Toast/ToastStorage.swift`
- Modify: `Mos/Components/Toast/ToastPanel.swift`
- Modify: `Mos/Localizable.xcstrings`

**Step 1: Remove storage/UI references**

Delete `showsFullText` persistence and remove the `Show Full Text` checkbox from the debug panel. Keep the panel behavior aligned with the new API by sending toasts without any wrap width override unless a future dedicated control is added.

**Step 2: Run verification**

Run the regression command again and then a focused app build:

`xcodebuild -project Mos.xcodeproj -scheme Debug -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO`

Expected: regression tests pass and build succeeds.

### Task 4: Review diff and document the behavior shift

**Files:**
- Review only

**Step 1: Inspect diff**

Run: `git diff -- Mos/AppDelegate.swift Mos/Components/Toast/Toast.swift Mos/Components/Toast/ToastManager.swift Mos/Components/Toast/ToastContentView.swift Mos/Components/Toast/ToastStorage.swift Mos/Components/Toast/ToastPanel.swift Mos/Localizable.xcstrings tools/regression/toast-regression-tests.swift docs/plans/2026-04-11-toast-wrap-width-refactor.md`

**Step 2: Summarize migration**

Note that:
- `expandMessage` is removed
- default behavior is now single-line
- positive `wrapWidth` is the only multiline trigger
