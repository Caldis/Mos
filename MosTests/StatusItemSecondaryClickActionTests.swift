import XCTest
@testable import Mos_Debug

/// Covers the status bar icon's secondary (right) click behaviour: how a click is
/// routed, how the icon reflects the shortcut toggle it is bound to, and the
/// persistence contract of the stored preference.
final class StatusItemSecondaryClickActionTests: XCTestCase {

    // MARK: - Persistence contract

    /// The raw values and the UserDefaults key are written to disk; renaming either
    /// silently resets the preference for every existing user.
    func testRawValues_areStable() {
        XCTAssertEqual(StatusItemSecondaryClickAction.menu.rawValue, "menu")
        XCTAssertEqual(StatusItemSecondaryClickAction.toggleSmooth.rawValue, "toggleSmooth")
        XCTAssertEqual(StatusItemSecondaryClickAction.toggleReverse.rawValue, "toggleReverse")
        XCTAssertEqual(StatusItemSecondaryClickAction.preferences.rawValue, "preferences")
        XCTAssertEqual(OptionItem.General.StatusItemSecondaryClickAction, "statusItemSecondaryClickAction")
    }

    /// Existing installs have no stored value; they must keep the pre-4.3 behaviour
    /// of popping up the menu on both mouse buttons.
    func testDefault_isShowMenu() {
        XCTAssertEqual(StatusItemSecondaryClickAction.default, .menu)
        XCTAssertEqual(StatusItemSecondaryClickAction(storedValue: nil), .menu)
        XCTAssertEqual(OPTIONS_GENERAL_DEFAULT().statusItemSecondaryClickAction, .menu)
    }

    func testStoredValue_isRestored() {
        XCTAssertEqual(StatusItemSecondaryClickAction(storedValue: "toggleReverse"), .toggleReverse)
        XCTAssertEqual(StatusItemSecondaryClickAction(storedValue: "preferences"), .preferences)
    }

    /// A value written by a newer Mos and then read back after a downgrade must not
    /// leave the preference in an unusable state.
    func testUnknownStoredValue_fallsBackToDefault() {
        XCTAssertEqual(StatusItemSecondaryClickAction(storedValue: "toggleTelekinesis"), .menu)
        XCTAssertEqual(StatusItemSecondaryClickAction(storedValue: ""), .menu)
    }

    /// The preferences pop up button maps its selected index straight onto
    /// `allCases`, so the order is part of the UI contract.
    func testAllCases_orderMatchesThePopUpButton() {
        XCTAssertEqual(StatusItemSecondaryClickAction.allCases, [.menu, .toggleSmooth, .toggleReverse, .preferences])
    }

    func testEveryCase_hasANonEmptyTitle() {
        for action in StatusItemSecondaryClickAction.allCases {
            XCTAssertFalse(action.localizedTitle.isEmpty, "\(action) has no pop up button title")
        }
    }

    // MARK: - Click routing

    /// The primary click must keep opening the menu whatever the user picked for
    /// the secondary click, otherwise the menu becomes unreachable.
    func testPrimaryClick_alwaysShowsTheMenu() {
        for action in StatusItemSecondaryClickAction.allCases {
            XCTAssertEqual(
                StatusItemSecondaryClickAction.outcome(isSecondaryClick: false, action: action, isAccessibilityTrusted: true),
                .showMenu,
                "a primary click with \(action) selected must still open the menu"
            )
        }
    }

    func testSecondaryClick_followsTheSelectedAction() {
        func outcome(_ action: StatusItemSecondaryClickAction) -> StatusItemClickOutcome {
            StatusItemSecondaryClickAction.outcome(isSecondaryClick: true, action: action, isAccessibilityTrusted: true)
        }
        XCTAssertEqual(outcome(.menu), .showMenu)
        XCTAssertEqual(outcome(.toggleSmooth), .toggleScroll(.smooth))
        XCTAssertEqual(outcome(.toggleReverse), .toggleScroll(.reverse))
        XCTAssertEqual(outcome(.preferences), .openPreferences)
    }

    /// Without accessibility access the scroll options do nothing, and the menu is
    /// the only place that can ask for the permission — so it has to win.
    func testSecondaryClick_showsTheMenuWithoutAccessibilityAccess() {
        for action in StatusItemSecondaryClickAction.allCases {
            XCTAssertEqual(
                StatusItemSecondaryClickAction.outcome(isSecondaryClick: true, action: action, isAccessibilityTrusted: false),
                .showMenu,
                "\(action) must not run silently while Mos is unauthorized"
            )
        }
    }

    // MARK: - Icon state

    func testIcon_dimsOnlyWhileTheBoundToggleIsOff() {
        func dims(_ action: StatusItemSecondaryClickAction, smooth: Bool, reverse: Bool) -> Bool {
            StatusItemSecondaryClickAction.iconAppearsDisabled(action: action, isSmoothEnabled: smooth, isReverseEnabled: reverse)
        }
        XCTAssertTrue(dims(.toggleSmooth, smooth: false, reverse: true))
        XCTAssertFalse(dims(.toggleSmooth, smooth: true, reverse: false))
        XCTAssertTrue(dims(.toggleReverse, smooth: true, reverse: false))
        XCTAssertFalse(dims(.toggleReverse, smooth: false, reverse: true))
    }

    /// The icon only ever reports the state of the toggle it is bound to; actions
    /// that toggle nothing must never dim it.
    func testIcon_staysBrightForNonToggleActions() {
        for action in [StatusItemSecondaryClickAction.menu, .preferences] {
            XCTAssertNil(action.toggledScrollOption)
            XCTAssertFalse(
                StatusItemSecondaryClickAction.iconAppearsDisabled(action: action, isSmoothEnabled: false, isReverseEnabled: false),
                "\(action) toggles nothing, so the icon has no state to report"
            )
        }
    }

    // MARK: - Reading and writing the scroll options

    func testScrollToggleOption_readsAndWritesTheMatchingField() {
        let options = OPTIONS_SCROLL_DEFAULT()
        options.smooth = true
        options.reverse = false

        XCTAssertTrue(ScrollToggleOption.smooth.isEnabled(in: options))
        XCTAssertFalse(ScrollToggleOption.reverse.isEnabled(in: options))

        ScrollToggleOption.smooth.setEnabled(false, in: options)
        XCTAssertFalse(options.smooth)
        XCTAssertFalse(options.reverse, "toggling smooth must not touch reverse")

        ScrollToggleOption.reverse.setEnabled(true, in: options)
        XCTAssertTrue(options.reverse)
        XCTAssertFalse(options.smooth, "toggling reverse must not touch smooth")
    }
}
