# Toast

Lightweight floating toast notification for macOS apps.

A modular, dependency-free component that displays non-intrusive, auto-dismissing notifications. Designed for menu bar apps and background utilities where system notifications are too heavy. Supports multiple simultaneous toasts, draggable positioning, and an interactive debug panel.

## Features

- **Multi-toast** -- Display up to 8 toasts simultaneously with automatic stacking
- **Adaptive stacking** -- Stacks downward when anchor is in upper half of screen, upward when in lower half
- **Draggable** -- Drag any toast to reposition; position is remembered across sessions
- **Non-activating** -- Uses `NSPanel` with `.nonactivatingPanel`, never steals focus
- **Frosted glass** -- `NSVisualEffectView` with per-OS-version material selection
- **4 styles** -- `.info`, `.success`, `.warning`, `.error` with accent color indicators
- **Auto-dismiss** -- Configurable duration with fade-out animation
- **Multi-monitor** -- Positions on the screen containing the mouse cursor
- **Deduplication** -- Same message currently visible is suppressed
- **Overflow eviction** -- Oldest toast fades out when max count is exceeded
- **Thread-safe** -- Always dispatches to main queue (safe from IOKit/CGEventTap callbacks)
- **Fullscreen-aware** -- `.fullScreenAuxiliary` collection behavior
- **Independent persistence** -- Uses its own `UserDefaults` suite, not the host app's
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

// Dismiss all visible toasts
Toast.dismissAll()

// Add debug panel to a menu (one line)
menu.addItem(Toast.debugMenuItem())
```

## API

```swift
struct Toast {
    enum Style: CaseIterable {
        case info       // Neutral, default icon
        case success    // Green accent
        case warning    // Orange accent
        case error      // Red accent
    }

    /// Show a toast notification.
    static func show(_ message: String,
                     style: Style = .info,
                     duration: TimeInterval = 2.5,
                     icon: NSImage? = nil)

    /// Dismiss all visible toasts.
    static func dismissAll()

    /// Open the interactive debug panel.
    static func showTestPanel()

    /// Create a self-contained NSMenuItem for the debug panel.
    /// Target, action, icon, and title are all built-in.
    static func debugMenuItem() -> NSMenuItem
}
```

## Architecture

```
Toast/ directory
├── Toast.swift            Public API (show, dismissAll, showTestPanel, debugMenuItem)
├── ToastManager.swift     Multi-toast lifecycle, stacking, dedup, eviction
├── ToastWindow.swift      Container NSPanel, drag-to-reposition, hit-test passthrough
├── ToastContentView.swift Visual rendering (frosted glass, icon, label, accent)
├── ToastStorage.swift     Independent UserDefaults persistence
└── ToastPanel.swift       Product-grade debug panel (NSObject, menu target)
```

Dependency flow: `Toast → ToastManager → ToastWindow → ToastContentView`, `ToastManager → ToastStorage`, `ToastPanel → Toast (public API)`

All types except `Toast` are `internal` -- consumers only interact with the `Toast` struct.

## Visual Adaptation

| macOS Version | Material | Icons |
|---------------|----------|-------|
| 10.13 | `.dark` | System built-in (`NSImage.cautionName`, etc.) |
| 10.14+ | `.hudWindow` + `.vibrantDark` | System built-in |
| 11.0+ | `.hudWindow` + `.vibrantDark` | SF Symbols |

## Debug Panel

Call `Toast.showTestPanel()` or add `Toast.debugMenuItem()` to a menu. The panel provides:

**Configuration:**
- Max simultaneous toasts (1-8, slider)
- Position status + reset to default

**Send Toast:**
- Message text input
- Style selector (button group)
- Duration slider (0.5s -- 10s)
- Custom icon toggle

**Quick Tests:**
- All Styles, Stack Test, Overflow, Dedup, Long Text, Dismiss All

## Integration

Copy the `Toast/` directory into any macOS project. No frameworks, no packages, no configuration. Persistence uses `UserDefaults(suiteName: "\(bundleID).toast")` so it won't conflict with your app's settings.

## License

Part of the [Mos](https://github.com/Caldis/Mos) project. Licensed under CC BY-NC 4.0.
