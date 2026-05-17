# ButtonCore Left Click Safety Design

## Overview

Re-scope `ButtonCore` so the default runtime path no longer places real primary mouse button events inside a global active `CGEventTap`. Preserve synthetic left-click mapping and drag behavior, but stop mutating or consuming real `leftMouseDown/leftMouseUp` events by default.

## Problem Statement

The current `ButtonCore` path installs a single `.defaultTap` interceptor over:

- `leftMouseDown`
- `leftMouseUp`
- `rightMouseDown`
- `rightMouseUp`
- `otherMouseDown`
- `otherMouseUp`
- `keyDown`
- `keyUp`

That active tap both matches bindings and injects virtual modifier flags into passthrough keyboard and mouse events. User testing showed a critical incompatibility: merely including real `leftMouseDown` in the active tap can leave some applications in a half-committed UI state even when the callback returns the original event unchanged.

## Goals

- Remove real primary-button clicks from the default active interception path
- Preserve stateful synthetic left-click mappings and drag behavior
- Preserve virtual modifier propagation for keyboard passthrough
- Keep the architecture explicit about which paths are safe by default and which are high-risk
- Add tests that lock down the new default behavior

## Non-Goals

- No app-specific workarounds
- No attempt to preserve virtual modifiers on real physical left-click passthrough in the default path
- No new UI or preferences for advanced primary-button interception in this iteration
- No rewrite of the existing synthetic mouse drag backend

## Current Behavioral Split

There are three distinct left-click-related flows:

1. Real physical left click observed by `ButtonCore`
2. Side button or other trigger mapped to synthetic left click via `ShortcutExecutor`
3. Synthetic mouse drag continuation handled by `MouseInteractionSessionController`

Only the first path requires touching real `leftMouseDown/leftMouseUp`. The second and third paths already operate on synthetic events or drag/move rewrite paths and do not require active interception of the user's real primary click.

## Recommended Architecture

### 1. Split `ButtonCore` into safe active dispatch plus passive primary observation

Replace the single `eventInterceptor` with two interceptors:

- `dispatchInterceptor`
  - `.defaultTap`
  - handles only:
    - `keyDown`
    - `keyUp`
    - `otherMouseDown`
    - `otherMouseUp`
- `primaryObservationInterceptor`
  - `.listenOnly`
  - observes only:
    - `leftMouseDown`
    - `leftMouseUp`
    - optionally `rightMouseDown`
    - optionally `rightMouseUp`

The passive observer exists only if we still want runtime visibility or future diagnostics around primary-button events. It must not consume events or mutate flags.

### 2. Narrow virtual modifier injection to safe passthrough events

Keep virtual modifier propagation for keyboard passthrough in `ButtonCore`, but stop mutating real physical mouse `down/up` events by default.

This means:

- real keyboard passthrough keeps virtual modifiers
- synthetic mouse actions still carry combined modifier flags through `ShortcutExecutor`
- drag/move rewrite continues to carry combined modifier flags through `MouseInteractionSessionController`
- real physical primary-button passthrough is left untouched

### 3. Keep synthetic drag behavior unchanged

`MouseInteractionSessionController` should remain responsible for:

- synthetic drag-session lifecycle
- move/drag rewrite
- virtual modifier propagation on movement/drag interaction events

This path is not implicated by the current bug report and should remain the single owner of drag rewriting.

### 4. Reframe primary-button combinations as advanced behavior

Today the codebase allows modifier-plus-primary-click recording. That creates a product/runtime mismatch if the default runtime no longer modifies real primary clicks.

For this iteration, the design chooses safety over capability:

- default runtime does not support virtual modifiers on real physical primary clicks
- default runtime does not rely on active interception of real primary clicks
- any future support for real primary-button interception should be isolated behind a clearly advanced or experimental path

## Testing Strategy

Add regression coverage for:

- default active `ButtonCore` mask excludes `left/right mouse down/up`
- passive observation mask includes the primary mouse buttons
- passthrough virtual modifier injection still applies to keyboard events
- passthrough virtual modifier injection no longer applies to real left-click events
- existing synthetic left-click action tests keep passing

## Tradeoffs

### What we gain

- Much lower risk of cross-app focus and activation breakage
- Clearer ownership boundaries between real-event observation and synthetic-event execution
- Tests that document the safe default contract

### What we lose

- Virtual modifier propagation onto real physical primary-button passthrough
- Full fidelity support for modifier-plus-primary-click trigger behavior in the default runtime path

## Future Extension Path

If advanced users still need modifier-plus-real-left-click support, add a dedicated isolated interceptor path later with all of these properties:

- opt-in only
- separate mask and callback from the safe default path
- separate tests
- explicit “unsafe/experimental” product framing

That future work should not block the safe-default fix.
