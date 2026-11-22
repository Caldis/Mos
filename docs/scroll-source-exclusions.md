# Scroll source exclusions

Some input utilities, such as TourBox Console, generate ordinary mouse-wheel
scroll events. Smoothing those events can interfere with the utility's intended
behavior. Source exclusions let a driver app's scrolling pass through unchanged
while a mouse continues to use Mos smoothing in the same drawing app.

## Configure an exclusion

1. Open Mos **Preferences → Scrolling → Scroll Source Exclusions…**.
2. Choose **Add…** and select the application that sends the scroll events, such
   as `/Applications/TourBox Console.app`.
3. Close the panel. Changes take effect immediately and persist across restarts.
   To undo the exclusion, select the source and choose **Remove**.

Select the sending utility, not the drawing app receiving the scrolling.
Exclusions apply globally and bypass smoothing, reversal and axis conversion,
including target application overrides. Duplicate selections select the existing
entry. Applications without a bundle identifier cannot be added.

The default list is empty. TourBox is not hard-coded or added automatically.
Astropad does not need an exclusion when Mos already recognizes its scrolling as
trackpad input.

## Identify the source

If you are unsure which app to select, disable smoothing for the affected target
application temporarily. Hold Option while opening the Mos menu and choose
**Debug: Event Monitor**. Scroll using only the affected device, then inspect
`eventSourceUnixProcessID` and run:

```bash
ps -p <source-pid> -o pid=,comm=
```

The monitor's `Path` describes the target application, not the source. A source
PID of zero or an unresolvable source cannot be excluded by application identity.
Restore the target application's smoothing after configuring the exclusion.

## Implementation and compatibility

- The scroll callback checks exclusions after Mos's synthetic-event guard and
  before parsing, scroll-action state changes or event modification. A match
  returns the original event; tap location, masks and posting behavior are unchanged.
- Matching uses the source process's bundle identifier, not its temporary PID,
  the target app, a driver-specific UserData marker or a physical HID device ID.
- A bounded cache holds at most 64 source lookups. Successful lookups expire
  after five seconds; failed lookups retry after one second. App launch/termination
  notifications and exclusion changes invalidate cached identities. The callback
  and configuration updates run on the main run loop.
- An empty list, PID zero, an unknown source or a non-match retains the existing
  processing path. Lookup failures never turn into a blanket exclusion.
- The independent UserDefaults string-array key is
  `excludedScrollSourceBundleIdentifiers`. Missing or malformed values read as an
  empty list; duplicate and empty identifiers are removed. Existing scroll keys
  and per-application serialized profiles are unchanged. Older versions ignore
  the new key; no data migration is required.
- New UI strings use `NSLocalizedString`, with English and Simplified Chinese
  translations. Other locales use the English source text until translations
  reviewed by speakers of those languages are contributed.

## Verification

The regression tests live in `MosTests/ScrollSourceFilterTests.swift`. Run them
using the shared `Debug` scheme and the safety instructions in
[`AGENTS.md`](../AGENTS.md) and the [testing matrix](../.agents/docs/testing.md).
In particular, quit running Mos instances before starting hosted tests.

For manual acceptance, enable smoothing in the target app, confirm that the
mouse remains smooth and the excluded utility works, then remove the exclusion
and verify the original behavior returns. Test unaffected trackpads or Astropad
separately. A local TourBox test does not establish compatibility with every driver.
