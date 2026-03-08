# Mos Crash Fix Design (2026-03-04, updated 2026-03-07)

## Scope

This document defines a low-intrusion, low-overhead fix plan for long-running crash patterns observed in Mos smooth scrolling pipeline.

The plan targets runtime stability only and does not change UI, preferences model, or smoothing algorithm behavior.

## Primary Evidence

Confirmed same-signature crash family across issues:

- https://github.com/Caldis/Mos/issues/868
- https://github.com/Caldis/Mos/issues/826
- https://github.com/Caldis/Mos/issues/699
- https://github.com/Caldis/Mos/issues/687
- https://github.com/Caldis/Mos/issues/665
- https://github.com/Caldis/Mos/issues/510
- https://github.com/Caldis/Mos/issues/512
- https://github.com/Caldis/Mos/issues/499
- https://github.com/Caldis/Mos/issues/368
- https://github.com/Caldis/Mos/issues/597
- https://github.com/Caldis/Mos/issues/859

Recurring stack signatures:

- `CVDisplayLink` thread + `_CFRelease` + malloc invalid free / free botch.
- `CVDisplayLink` thread + `CGSDeepCopyEventRecord` / `SLEventCreateCopy` + PAC trap (`EXC_BREAKPOINT`).
- Main thread crash in `processEventTapData` / `SLEventTapPostEvent` / encoding path.

Cross-version, cross-arch, cross-OS consistency:

- Mos: 3.3.2 -> 4.0.0-beta.
- CPU: Intel + Apple Silicon.
- macOS: 12.x -> 26.x.

## Root Cause Model (pre-fix path)

### Root Cause A: Event/Proxy Lifetime Violation

In the pre-fix implementation, `ScrollPoster` stored callback-scoped `event` and `proxy` and reused them later across frames:

- `ref` stores both event and proxy.
- Event is later copied and posted asynchronously.
- Posting is detached from original event tap callback timing.

Relevant pre-fix code:

- `Mos/ScrollCore/ScrollPoster.swift` lines around `ref`, `update`, `emitPhase`, `post`.
- `DispatchQueue.main.async { eventClone.tapPostEvent(proxy) }` appears in two places.

This violates assumptions for callback-scoped objects, especially under tap restart, run loop shifts, or prolonged uptime.

### Root Cause B: Unsynchronized Cross-Thread State Access

`ScrollPoster` mutable state is read/written from:

- Event tap callback path (main-thread run loop).
- `CVDisplayLink` callback thread.

Shared mutable fields include:

- `current`, `buffer`, `delta`, `ref`, momentum/tracking flags, timing fields.
- `ScrollPhase.shared` transitions called from both sides.

In the pre-fix design, no explicit synchronization existed.

### Root Cause C: Async Posting of Stale Frame Context

In the pre-fix path, posting used async dispatch to main queue, which could run after:

- `stop()/reset()`.
- tap disable/enable cycle.
- source app focus changes.

Old frames can outlive their valid generation and use stale context.

### Amplifier: Interceptor Auto-Restart

`Interceptor` keeper restart logic increases chance of context invalidation windows.

It is not the direct crash root but amplifies stale object usage.

## Design Goals

- Keep behavior equivalent for end users.
- Avoid heavy architectural rewrites.
- Minimize CPU overhead and lock contention.
- Eliminate proxy lifetime violation by using proxy-independent posting (`CGEvent.post`).
- Eliminate stale async frame emission after stop/reset/restart via generation + TTL guards.

## Chosen Direction (2026-03-08 — revised)

### Initial approach (2026-03-07): proxy retention with TTL guard

The first implementation kept `tapPostEvent(proxy)` and attempted to bound proxy reuse with generation + TTL guards inside `ScrollDispatchContext`. This shipped as v4.0.1.

**Result**: Crash persisted. User reports in issue #868 confirmed that `processEventTapData` use-after-free still occurred because `tapPostEvent(proxy)` fundamentally requires the proxy to be called within the original event tap callback scope. Retaining and reusing it from an async queue violates Apple's internal invariant regardless of how short the retention window is.

### Second attempt (2026-03-08): `CGEvent.post(tap: .cgAnnotatedSessionEventTap)`

Completely removed proxy from the dispatch chain and used `CGEvent.post(tap: .cgAnnotatedSessionEventTap)` instead.

**Result**: Crash fixed, but introduced UX regression. `CGEvent.post(tap:)` reinjects events at the session event tap chain top, causing the OS to re-route based on current cursor position. When the user moves the cursor to a different window during momentum deceleration, scroll events follow the cursor to the new window instead of continuing in the original target — a behavior regression from the early `tapPostEvent(proxy)` design.

### Current approach (2026-03-08): `CGEvent.postToPid(targetPID)`

Uses `CGEvent.postToPid(_:)` to deliver synthetic scroll events directly to the original target process.

Key changes:
- `ScrollDispatchContext` captures `targetPID` (via `eventTargetUnixProcessID`) at event snapshot time
- `PostingSnapshot` contains `event`, `targetPID`, `generation`, `capturedAt`
- `enqueue()` calls `snapshot.event.postToPid(snapshot.targetPID)` on a serial queue
- Events are delivered directly to the target process's event queue, bypassing the session event tap chain entirely
- The process internally routes the event to the correct window via the event's `location` field
- Synthetic event marker (`eventSourceUserData = 0x4D4F53534D4F4F54`) retained as defensive bypass in the scroll callback
- Generation guard and TTL guard (5.0s) remain as safety nets for stale frame rejection

This solves all three problems simultaneously:
1. **Crash**: No proxy retained — `postToPid` is thread-safe and proxy-independent
2. **Routing**: Events always reach the original target process, regardless of cursor movement
3. **Re-entry**: Events don't traverse the event tap chain, so no re-smoothing risk (marker bypass is purely defensive)

## Proposed Fix Strategy

## 1) Isolate Dispatch Lifecycle in a Dedicated Context Module

Introduce `ScrollDispatchContext` as the only owner of cross-frame dispatch state.

State held in the module:

- `eventTemplate`
- `targetPID`
- `generation`
- `updatedAt`
- serial `postQueue`

This keeps lifecycle control cohesive and shrinks the behavioral diff inside `ScrollPoster`.

## 2) Snapshot Event Template at Update Time

At `ScrollPoster.update(...)`:

- immediately take `event.copy()` as a stable template
- hand the copied template to `ScrollDispatchContext`
- abort the smoothing update safely if snapshotting fails

Subsequent synthetic frames are copied from the stored template, not from the callback-owned `event`.

## 3) Post via `CGEvent.postToPid(targetPID)`

Use proxy-independent, process-targeted posting:

- capture `eventTargetUnixProcessID` from the original event at snapshot time
- enqueue posts on a dedicated serial queue
- before the actual post, validate `targetPID != 0`, `generation`, and a 5.0s event TTL
- call `snapshot.event.postToPid(snapshot.targetPID)` if the snapshot is valid
- events are delivered directly to the target process, preserving correct routing during momentum
- synthetic event marker retained as defensive bypass (events no longer re-enter tap chain)

## 4) Add Synthetic Event Tag and Fast Bypass

Mark generated smooth events via `eventSourceUserData`.

In `ScrollCore.scrollEventCallBack` early path:

- detect the marker
- bypass immediately with `passUnretained`
- optionally count bypasses in `DEBUG`

Even with proxy-based posting retained, this defensive bypass prevents accidental self-reprocessing if tap position or callback behavior changes.

## 5) Add Generation Guard to Drop Stale Async Frames

Each queued post captures the current `generation`.

- increment generation on `stop()`
- increment generation on `reset()`
- increment generation on explicit invalidation/restart boundaries
- drop queued frames whose generation no longer matches

This prevents stale tail frames from old sessions from posting after stop/reset/restart.

## 6) Add Event TTL Guard

Each dispatch snapshot carries `capturedAt` (the time the event template was captured).

- if `now - capturedAt > eventTTL (5.0s)`, do not post
- clear the stored template on reset/cleanup

The 5.0s TTL covers the longest expected momentum deceleration phase (typically 1-3s, extreme ~5s). TTL is only checked at `enqueue()` time as a safety net, not at snapshot creation.

## 7) Add Lightweight Synchronization Around Poster State

Protect mutable `ScrollPoster` state with one `os_unfair_lock`.

Protected state includes:

- current interpolation state
- buffer/delta
- timing flags
- shift state
- phase-related transitions performed inside poster flow

Rule:

- lock only for mutation/snapshot decisions
- never execute the actual event post while holding the poster lock

## 8) Keep ScrollPhase Semantics, Synchronize Access

Do not redesign the phase machine.

Keep the current phase transitions, but ensure poster-side transitions and frame emission decisions happen in synchronized critical sections so phase and motion state do not tear across callback thread and display-link thread.

## 9) Defensive Cleanup on Tap Lifecycle Changes

When the tap is disabled or restarted:

- force `ScrollPoster.stop(.TrackingEnd)`
- invalidate outstanding dispatch generations
- clear retained dispatch context before the next session starts

This is applied both from scroll tap disable callbacks and from `Interceptor.restart()`.

## Detailed Implementation Plan

### File 1: `Mos/ScrollCore/ScrollDispatchContext.swift` (new primary module)

Changes:

- Introduce `PostingSnapshot` with:
  - copied `event`
  - `targetPID` (from `eventTargetUnixProcessID`)
  - captured `generation`
  - `capturedAt` timestamp
- Store shared dispatch state:
  - `eventTemplate`
  - `targetPID`
  - `generation`
  - `updatedAt`
- Add one internal `os_unfair_lock`.
- Add serial post queue.
- Provide:
  - `capture(event:)` — extracts and stores target PID from event
  - `preparePostingSnapshot()` — guards `targetPID != 0`
  - `enqueue(_:)` — uses `event.postToPid(targetPID)` for direct process delivery
  - `advanceGeneration()`
  - `clearContext()` — clears PID to 0
  - `invalidateAll()` — clears PID to 0
- In `DEBUG`, expose lightweight counters for confidence during stress runs.

### File 2: `Mos/ScrollCore/ScrollPoster.swift`

Changes:

- Keep smoothing math and phase flow intact.
- Remove direct ownership of async post queue / generation bookkeeping.
- Change `update(...)` to hand snapshot capture to `ScrollDispatchContext` (no proxy parameter).
- Change `emitPhase(...)` and `post(...)` to request posting snapshots from the context.
- Post events via `event.postToPid(targetPID)` through the dispatch context.
- Keep Chrome-specific stop tail behavior, but source the event from a fresh posting snapshot.
- Keep `stop()`/`reset()` responsible for invalidation and cleanup boundaries.

### File 3: `Mos/ScrollCore/ScrollCore.swift`

Changes:

- Call `ScrollPoster.shared.update(event:duration:y:x:speed:amplification:)` without proxy.
- Add early bypass for synthetic smooth events.
- On tap disable (`tapDisabledByTimeout` / `tapDisabledByUserInput`), force poster cleanup immediately.
- Keep existing remote-source, trackpad, and per-app behavior unchanged.

### File 4: `Mos/ScrollCore/ScrollUtils.swift`

Changes:

- Add minimal helpers for synthetic event tagging/checking.
- Keep helper local to scroll pipeline support code.

### File 5: `Mos/Utils/Interceptor.swift`

Changes:

- Keep architecture unchanged.
- Add defensive `ScrollPoster.stop(.TrackingEnd)` in restart boundary before re-enabling the tap.

## Behavioral Compatibility

Should remain unchanged:

- User-facing smoothness parameters.
- Per-app settings behavior.
- Hotkey behavior (`dash`, `toggle`, `block`).
- Sim trackpad phase progression semantics.

Potential tiny differences:

- In race windows during stop/restart, trailing stale frame may be dropped instead of posted.
- This is acceptable and preferred over crash.
- Very-late queued posts may be dropped by TTL (5.0s) instead of being emitted after context expiry.

## Performance Impact Assessment

Added cost:

- One extra `event.copy()` per physical input update.
- One lightweight lock/unlock per poster state transition path.
- One lightweight lock/unlock in dispatch-context snapshot/post validation path.
- One generation comparison per queued post.
- One TTL comparison per queued post.
- One serial dispatch hop before `event.postToPid(targetPID)`.
- One `getIntegerValueField(.eventTargetUnixProcessID)` per physical input update.

Reduced risk/cost:

- Proxy lifetime violation eliminated entirely — no proxy retained beyond callback scope.
- No event tap chain re-traversal — `postToPid` bypasses all taps, delivering directly to the target process.
- Correct momentum routing — scroll events stay in the original target window even if cursor moves.
- Fewer crash/restart disruptions from stale context use.

Expected user-perceived impact:

- No visible degradation in normal use.

## Risk Matrix

1. Event TTL (5.0s) may drop a very-late tail frame
- Mitigation: 5.0s covers expected momentum deceleration; only affects truly stale dispatches.

2. Event order differences in specific apps
- Mitigation: serial post queue; preserve current phase and delta write order.

3. Synthetic marker compatibility
- Mitigation: marker plus secondary fallback checks if needed.

4. Proxy lifetime crash (eliminated)
- Root cause removed: proxy is no longer retained or used beyond the callback. `CGEvent.post(tap:)` is proxy-independent.

5. Deadlock risk due to locking
- Mitigation: strict rule not to post events under lock.

## Validation Plan

## Crash Reproduction Stress

- Rapid continuous wheel scrolling for 30+ minutes.
- Mix vertical/horizontal and shift remap.
- Switch active apps frequently while scrolling.

## Long-Run Stability

- 24h+ uptime.
- Repeated sleep/wake cycles.
- Observe whether Mos silently exits.

## Feature Regression

- Sim trackpad mode on/off.
- Reverse options per axis.
- Per-app smooth override.
- Hotkeys behavior.

## Environment Matrix

- macOS 26.2/26.3 Apple Silicon.
- macOS 15.x Apple Silicon and Intel where available.
- Apps: Safari, Chrome, IDE, Finder.

## Logging for Confidence

Add debug counters (dev build only):

- `postedFrames`
- `droppedFramesByGeneration`
- `droppedFramesByTTL`
- `skippedSyntheticEvents`
- `updateSnapshotFailures`

## Rollout Plan

1. Internal test build for users in issues #859/#868/#665.
2. 72h targeted feedback window.
3. Beta release.
4. Stable release if no same-signature crash reports.

## Non-Goals in This Patch

- Rewriting interpolation/filter algorithm.
- Replacing `CVDisplayLink`.
- Refactoring options model or UI.
- Solving unrelated crash signatures (for example pure XPC/LaunchServices paths).

## Implementation Order

1. Implement `ScrollDispatchContext` for lifecycle, queueing, generation, TTL, and target PID tracking.
2. Rewire `ScrollPoster` to use the new context while preserving smoothing flow.
3. Replace `tapPostEvent(proxy)` with `event.postToPid(targetPID)` for direct process delivery.
4. Add synthetic marker and bypass in scroll callback.
5. Add tap-disable and interceptor restart cleanup hooks.
6. Add minimal diagnostics and run stress checks.

## Acceptance Criteria

- No crash in known signatures under stress testing.
- No user-visible smooth scrolling regression.
- No duplicate self-smoothed event loop.
- No stale-frame emission after stop/reset/restart boundaries.
