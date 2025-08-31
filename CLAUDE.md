# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
./create-dmg.command
```

### Running and Development
- Open `Mos.xcodeproj` in Xcode
- Build and run normally (⌘+R)
- App requires accessibility permissions to function properly
- Use the Monitor window during development to visualize scroll events

## Architecture Overview

Minimum macOS version: 10.13, all API should be compatible with it

### Core Components

**ScrollCore Engine** (`Mos/ScrollCore/`):
- **ScrollCore.swift**: Main scrolling interception and processing engine
- **ScrollPoster.swift**: Smooth scroll event posting using CVDisplayLink
- **Interpolator.swift**: Smooth scrolling interpolation algorithms
- **ScrollEvent.swift**: Event data structures
- **ScrollFilter.swift**: Event filtering and processing logic

**Manager Pattern** (`Mos/Managers/`):
- **WindowManager**: Controls window lifecycle and presentation
- **StatusItemManager**: Menu bar status item and menu management  
- **PopoverManager**: Popover UI component management
- **DesktopManager**: Desktop-related functionality

**Configuration System** (`Mos/Options/`):
- **Options.swift**: Centralized configuration using UserDefaults
- **ExceptionalApplication.swift**: Per-application settings overrides

### Window Architecture

The app uses multiple specialized windows:

**IntroductionWindow**: First-time setup and permission requests
**PreferencesWindow**: Complex tabbed preferences with multiple view controllers
**MonitorWindow**: Real-time scroll event visualization
**WelcomeWindow**: User onboarding experience

Each window follows the WindowController + ViewController pattern.

### Key Technical Details

**Event Interception**: Uses CGEventTap for low-level mouse event capture
**Smooth Scrolling**: CVDisplayLink-based event posting for 60fps smoothness
**Permissions**: Requires accessibility permissions (LSUIElement=true for menu bar app)
**Localization**: Supports 12 languages with full storyboard localization

## File Structure Patterns

**Managers**: Singleton pattern for system integration
**Windows**: WindowController + ViewController pairs
**ScrollCore**: Core scrolling logic and algorithms
**Utils**: Utility classes including event monitoring and logging
**Popovers**: Menu bar popover interface components

## Development Guidelines

### Adding New Features
1. Follow the manager pattern for system integration
2. Use WindowController + ViewController for new windows
3. Add configuration options to `Options.swift`
4. Consider per-app exceptions via `ExceptionalApplication`

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

## Important Considerations

**Accessibility**: App requires accessibility permissions to intercept events
**System Integration**: Menu bar app behavior, auto-launch functionality
**Performance**: Real-time event processing at system level
**Localization**: All UI strings must be localized
**Distribution**: Cannot be uploaded to App Store per license restrictions