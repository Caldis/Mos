# ButtonCore Left Click Safety Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `ButtonCore` safe by default by removing real primary mouse button events from the global active tap while preserving synthetic left-click mappings, drag behavior, and keyboard virtual modifier passthrough.

**Architecture:** Split `ButtonCore` into a safe active dispatch interceptor and a passive primary-button observer, then update tests to reflect the new default contract. Keep `ShortcutExecutor` and `MouseInteractionSessionController` as the owners of synthetic click and drag behavior.

**Tech Stack:** Swift, CoreGraphics `CGEventTap`, existing `Interceptor`, `ButtonCore`, `InputProcessor`, `ShortcutExecutor`, `MouseInteractionSessionController`, `XCTest`, `xcodebuild test`

---

### Task 1: Add failing tests for the new safe-default contract

**Files:**
- Modify: `MosTests/InputProcessorTests.swift`

**Step 1: Write the failing tests**

Add tests that assert:

- the default active `ButtonCore` mask excludes `leftMouseDown`, `leftMouseUp`, `rightMouseDown`, `rightMouseUp`
- a dedicated passive observation mask includes those events
- passthrough virtual modifier injection still applies to keyboard events
- passthrough virtual modifier injection no longer applies to real left-click passthrough

**Step 2: Run the focused tests to verify they fail**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/InputProcessorTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: the new assertions fail because `ButtonCore` still exposes a single full active mask and still injects virtual modifiers into real left-click passthrough.

**Step 3: Commit nothing yet**

Do not commit in red state.

### Task 2: Refactor `ButtonCore` into dispatch and observation responsibilities

**Files:**
- Modify: `Mos/ButtonCore/ButtonCore.swift`
- Test: `MosTests/InputProcessorTests.swift`

**Step 1: Split masks and interceptors**

Introduce separate masks and interceptor storage:

- `dispatchEventMask`
- `primaryObservationEventMask`
- `dispatchInterceptor`
- `primaryObservationInterceptor`

**Step 2: Keep the active path narrow**

Make the active `.defaultTap` cover only:

- `keyDown`
- `keyUp`
- `otherMouseDown`
- `otherMouseUp`

**Step 3: Add a passive primary observer**

Create a `.listenOnly` interceptor for:

- `leftMouseDown`
- `leftMouseUp`
- `rightMouseDown`
- `rightMouseUp`

The callback may still feed `InputProcessor` if needed for future diagnostics, but it must not consume or mutate the event in this iteration.

**Step 4: Narrow virtual modifier injection**

Limit the active dispatch callback so virtual modifiers are only injected into safe passthrough events, starting with keyboard passthrough. Real primary-button passthrough must be left untouched.

**Step 5: Run the focused tests**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/InputProcessorTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: the new safe-default tests pass without breaking the existing synthetic mouse action tests.

**Step 6: Commit**

```bash
git add Mos/ButtonCore/ButtonCore.swift MosTests/InputProcessorTests.swift docs/plans/2026-04-15-buttoncore-left-click-safety-design.md docs/plans/2026-04-15-buttoncore-left-click-safety.md
git commit -m "fix(buttons): make primary click interception safe by default"
```

### Task 3: Verify behavior at the boundary we actually changed

**Files:**
- Modify: none unless a test failure exposes a gap
- Test: `MosTests/InputProcessorTests.swift`
- Test: `MosTests/MouseInteractionSessionControllerTests.swift`

**Step 1: Run focused regression coverage**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/InputProcessorTests -only-testing:MosTests/MouseInteractionSessionControllerTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: all focused interaction tests pass.

**Step 2: Re-check the new contract**

Confirm from code and tests that:

- real primary-button events are no longer in the default active tap mask
- synthetic left-click mappings still emit `.leftMouseDown/.leftMouseUp`
- drag-session behavior remains owned by `MouseInteractionSessionController`

**Step 3: Commit only if verification is green**

If verification fails, stop and fix the specific regression before any commit.
