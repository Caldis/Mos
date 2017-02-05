This is an attempt to specify some of the parts of the library so that it’s easier to spot bugs and regressions.

The specification is expected to grow incrementally, as the developers update various parts of the code. If you hack on a part of the library that would benefit from a precise specification and is not documented here yet, please consider adding to the specification.

Please stay high-level when writing the spec, do not document particular classes or other implementation details. The spec should be usable as a testing scenario – you should be able to walk through the spec and verify correct code behaviour on the library demo app.

# Recording Shortcuts

* If a shortcut has no modifiers and is not a function key (F1–F20), it must be rejected. (Examples: `A`, Shift-A.)
* If the shortcut is plain Esc without modifiers, it must be rejected and cancels the recording.
* If the shortcut is plain Backspace or plain Delete, it must be rejected, clears the recorded shortcut and cancels the recording.
* If the shortcut is Cmd-W or Cmd-Q, the recording must be cancelled and the keypress passed through to the system, closing the window or quitting the app.
* If a shortcut is already taken by system and is enabled, it must be rejected. (Examples: Cmd-S, Cmd-N. TBD: What exactly does it mean that the shortcut is “enabled”?)
* TBD: Option-key handling.
* All other shortcuts must be accepted. (Examples: Ctrl-Esc, Cmd-Delete, F16.)

# Formatting Shortcuts

On different keyboard layouts (such as US and Czech), a single shortcut (a combination of physical keys) may be formatted into different strings.

For example, the default system shortcut for toggling directly to Space #2 is Control–2. But when you switch to the Czech keyboard layout, the physical key with the `2` label now inserts the `ě` character. Thus, on most keyboard layouts the shortcut for toggling to Space #2 is called `^2`, but on the Czech layout it’s called `^ě`. (I stress that this is the same combination of hardware keys and the same `MASShortcut` instance.)

This is reflected by the system: When you open the System Preferences → Keyboard → Shortcuts pane, the shortcuts displayed depend on the currently selected keyboard layout (try switching between the US and Czech keyboard layouts and reopening the preference pane).

This means that the identity of a shortcut is given by its key code and modifiers (such as `kVK_ANSI_2` and `NSControlKeyMask`), not the `keyCodeString` returned by the `MASShortcut` class. This string may change depending on the current keyboard layout: `^2` with the US keyboard active, but `^ě` with the Czech keyboard active.
