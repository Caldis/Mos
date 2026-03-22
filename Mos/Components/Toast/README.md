# Toast

Lightweight floating toast notification for macOS apps.

A single-file, dependency-free component that displays non-intrusive, auto-dismissing notifications. Designed for menu bar apps and background utilities where system notifications are too heavy.

## Features

- **Non-activating** -- Uses `NSPanel` with `.nonactivatingPanel`, never steals focus
- **Frosted glass** -- `NSVisualEffectView` with per-OS-version material selection
- **4 styles** -- `.info`, `.success`, `.warning`, `.error` with accent color indicators
- **Auto-dismiss** -- Configurable duration with fade-out animation
- **Multi-monitor** -- Positions on the screen containing the mouse cursor
- **Deduplication** -- Same message within 0.5s is suppressed
- **Replace, not stack** -- New toast replaces current one instantly
- **Thread-safe** -- Always dispatches to main queue (safe from IOKit/CGEventTap callbacks)
- **Fullscreen-aware** -- `.fullScreenAuxiliary` collection behavior
- **macOS 10.13+** -- Graceful fallback for icons and visual effects

## Usage

```swift
// Basic
Toast.show("Operation completed")

// With style
Toast.show("Settings saved", style: .success)
Toast.show("Device does not support this feature", style: .warning)
Toast.show("Connection failed", style: .error)

// Full customization
Toast.show("Custom message",
           style: .info,
           duration: 5.0,
           icon: NSImage(named: "custom-icon"))
```

## API

```swift
struct Toast {
    enum Style {
        case info       // Neutral, default icon
        case success    // Green accent
        case warning    // Orange accent
        case error      // Red accent
    }

    /// Show a toast notification.
    /// - Parameters:
    ///   - message: Text to display (max 2 lines, truncated)
    ///   - style: Visual style (default: .info)
    ///   - duration: Seconds before auto-dismiss (default: 2.5)
    ///   - icon: Custom icon, nil uses style default
    static func show(_ message: String,
                     style: Style = .info,
                     duration: TimeInterval = 2.5,
                     icon: NSImage? = nil)

    /// Open the interactive test panel (debug builds).
    static func showTestPanel()
}
```

## Architecture

```
Toast (public API, static methods)
  |
  v
ToastWindow (singleton, window lifecycle + positioning + animation + dedup)
  |
  v
ToastContentView (NSVisualEffectView + icon + label + accent indicator)
  |
  v
ToastTestPanel (interactive test UI, self-contained)
```

All types except `Toast` are `private` -- the entire component is a single file with zero external dependencies beyond AppKit.

## Visual Adaptation

| macOS Version | Material | Icons |
|---------------|----------|-------|
| 10.13 | `.dark` | System built-in (`NSImage.cautionName`, etc.) |
| 10.14+ | `.hudWindow` + `.vibrantDark` | System built-in |
| 11.0+ | `.hudWindow` + `.vibrantDark` | SF Symbols |

## Test Panel

Call `Toast.showTestPanel()` to open an interactive panel with:

- Message text input
- Style selector (Info / Success / Warning / Error)
- Duration slider (0.5s -- 10s)
- Custom icon toggle
- Quick test buttons: All Styles, Rapid Fire (dedup), Long Text, Replace

## Integration

Drop `Toast.swift` into any macOS project. No frameworks, no packages, no configuration.

## License

Part of the [Mos](https://github.com/Caldis/Mos) project. Licensed under CC BY-NC 4.0.
