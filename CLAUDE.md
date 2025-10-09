# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## IMPORTANT

This Project's macoOS Deployment Target 10.13+, so every API should be compatible with it.

## Project Overview

Mos is a macOS utility application that provides smooth scrolling for mouse wheels, making them behave more like trackpads. Built with Swift and Xcode, it's a menu bar application that intercepts and modifies scroll events in real-time.

## Build System & Development Commands

### Building the Application
- **Primary IDE**: Xcode (requires Xcode 9.0+, Swift 4.0+)
- **Project File**: `Mos.xcodeproj`
- **Build Target**: macOS application bundle

### Dependencies
- **Charts**: Data visualization for the monitor window
- **LoginServiceKit**: Auto-launch functionality
- Dependencies are managed via Swift Package Manager (SPM)

### Creating Distribution Package
```bash
cd dmg/
# Requires create-dmg tool: https://github.com/create-dmg/create-dmg
# Requires Mos.app in dmg/ directory (copy from build output)
./create-dmg.command
```

The script automatically:
- Reads version from Info.plist
- Creates DMG with custom background and icon
- Generates versioned DMG filename (Mos.X.X.X.dmg)
- Includes application and Applications folder link

### Running and Development

**First-time setup:**
```bash
# 1. Open the project
open Mos.xcodeproj

# 2. Xcode will automatically resolve SPM dependencies (Charts, LoginServiceKit)
# 3. Wait for package resolution to complete (shown in top status bar)
# 4. Build and run (⌘+R)
```

**Runtime requirements:**
- App requires Accessibility permissions to intercept events
- On first launch, grant permissions in System Preferences → Security & Privacy → Accessibility
- Use the Monitor window during development to visualize scroll events in real-time

## Architecture Overview

Minimum macOS version: 10.13, all API should be compatible with it

### Core Components

**ScrollCore Engine** (`Mos/ScrollCore/`):
- **ScrollCore.swift**: Main scrolling interception and processing engine
- **ScrollPoster.swift**: Smooth scroll event posting using CVDisplayLink
- **Interpolator.swift**: Smooth scrolling interpolation algorithms
- **ScrollEvent.swift**: Event data structures
- **ScrollFilter.swift**: Event filtering and processing logic

**ButtonCore System** (`Mos/ButtonCore/`):
- **ButtonCore.swift**: Core mouse button event interception and processing
- **ButtonFilter.swift**: Event filtering logic for button actions
- **ButtonUtils.swift**: Button binding configuration utilities
- **ShortcutExecutor.swift**: System shortcut execution engine

**Key Recording System** (`Mos/Keys/`):
- **KeyRecorder.swift**: Event recording orchestrator with timeout protection
- **KeyPopover.swift**: Popover UI component for displaying recording status
- **KeyPreview.swift**: Visual preview of recorded key combinations
- **KeyCode.swift**: Comprehensive keyboard and mouse button code mappings
- **SystemShortcut.swift**: System shortcut definitions and management

**Manager Pattern** (`Mos/Managers/`):
- **WindowManager**: Controls window lifecycle and presentation
- **StatusItemManager**: Menu bar status item and menu management
- **ShortcutManager**: Global shortcut registration and management

**Configuration System** (`Mos/Options/`):
- **Options.swift**: Centralized configuration using UserDefaults
- **Application.swift**: Per-application settings and exception handling

### Window Architecture

The app uses multiple specialized windows:

**IntroductionWindow**: First-time setup and permission requests
**PreferencesWindow**: Complex tabbed preferences with multiple view controllers:
  - GeneralView: Basic scrolling settings
  - ScrollingView: Advanced scrolling configuration options
  - ButtonsView: Mouse button recording and action binding
  - ApplicationView: Per-application exception rules
  - AboutView: Application information and credits
  - UpdateView: Update checking and management
**MonitorWindow**: Real-time scroll event visualization using Charts framework
**WelcomeWindow**: User onboarding experience

Each window follows the WindowController + ViewController pattern.

### Key Technical Details

**Event Interception**: Uses `Interceptor` utility (wraps CGEventTap) for low-level event capture
  - ScrollCore: Captures scroll wheel events (scrollWheel)
  - ButtonCore: Captures mouse button events (leftMouseDown, rightMouseDown, otherMouseDown) and key events
**Smooth Scrolling**: CVDisplayLink-based event posting for 60fps smoothness via ScrollPoster
**Event Recording**: `KeyRecorder` orchestrates event capture with timeout protection and visual feedback
**Permissions**: Requires accessibility permissions (LSUIElement=true for menu bar app)
**Localization**: Supports 11 languages + English with dual .xcstrings system
**Per-App Settings**: `Application` class enables different scroll behaviors per application
**Singleton Pattern**: Core systems (ScrollCore, ButtonCore, Options, managers) use singleton pattern

## File Structure Patterns

**Managers**: Singleton pattern for system integration (WindowManager, StatusItemManager, ShortcutManager)
**Windows**: WindowController + ViewController pairs, each in separate subdirectories
**ScrollCore**: Core scrolling logic and algorithms (ScrollCore, ScrollPoster, Interpolator, ScrollFilter)
**ButtonCore**: Mouse button event handling and shortcut execution
**Keys**: Key/mouse event recording system (KeyRecorder, KeyPopover, KeyPreview, KeyCode, SystemShortcut)
**Utils**: Utility classes (Interceptor for CGEventTap, EventMonitor, Logger, Constants)
**Extension**: Swift extensions for CGEvent and other system types
**Options**: Configuration management (Options, Application)
**Components**: Reusable UI components (PrimaryButton)

## Development Guidelines

### Adding New Features
1. Follow the manager pattern for system integration
2. Use WindowController + ViewController for new windows
3. Add configuration options to `Options.swift`
4. Consider per-app exceptions via `Application` class
5. For button-related features, extend `ButtonCore` system and use `KeyRecorder` for event capture
6. UI components should support both Light and Dark mode with dynamic color adaptation
7. Use `Interceptor` utility (in Utils/) to wrap CGEventTap for event interception
8. Follow localization patterns - all strings must be localizable

### Modifying Scroll Behavior  
- Core logic is in `ScrollCore/ScrollCore.swift`
- Interpolation algorithms in `ScrollCore/Interpolator.swift` 
- Event filtering in `ScrollCore/ScrollFilter.swift`

### UI Changes
- Storyboard files are localized - modify Base.lproj first
- Follow existing popover patterns for menu bar UI
- Monitor window uses Charts framework for visualization

### Testing
- Test with various mouse types and scroll behaviors
- Verify accessibility permissions are properly requested
- Test per-application exception system
- Use Monitor window to verify scroll event processing

### Common Development Issues

**Build fails with SPM errors:**
```bash
# Clear SPM cache and DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData
# Re-resolve packages in Xcode: File → Packages → Reset Package Caches
```

**Scrolling not working at runtime:**
- Check Accessibility permissions in System Preferences → Security & Privacy → Accessibility
- Verify `ScrollCore.shared.start()` is called after permissions granted
- Use Monitor window to verify events are being captured

**Button bindings not triggering:**
- Open Monitor window to see if events are being captured
- Check `ButtonCore.shared.start()` is called
- Verify key codes in `KeyCode.swift` match expected values

**UI not updating after preference changes:**
- Options are stored in UserDefaults - verify `Options.shared` singleton is being used
- Check if NotificationCenter observers are properly registered
- Preferences window uses bindings - verify `@objc dynamic` on properties

## Localization

The app supports 12 languages using Xcode's String Catalog system (.xcstrings).

**Two separate localization files:**
- `Mos/Localizable.xcstrings` - Code strings via `NSLocalizedString()`
- `Mos/mul.lproj/Main.xcstrings` - Auto-generated from Storyboard (never merge these)

**Key requirements:**
- Use `NSLocalizedString()` (not `String(localized:)`) for macOS 10.13 compatibility
- Follow macOS official terminology (e.g., "偏好设置" not "设置")
- Preserve modifier key symbols: ⌘⌥⌃⇧
- Never translate: "Mos", person names, brand names

**For detailed translation guidelines, see `LOCALIZATION.md`**

## Important Considerations

**Accessibility**: App requires accessibility permissions to intercept events
**System Integration**: Menu bar app behavior, auto-launch functionality
**Performance**: Real-time event processing at system level
**Localization**: All UI strings must be localized following the guidelines above
**Distribution**: Cannot be uploaded to App Store per license restrictions