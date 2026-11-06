//
//  ScrollHotkeyTests.swift
//  MosTests
//
//  ScrollHotkey 结构体匹配逻辑测试 (Task 10)
//

import XCTest
@testable import Mos_Debug

final class ScrollHotkeyTests: XCTestCase {

    // MARK: - 初始化

    func testInit_keyboard() {
        let hotkey = ScrollHotkey(type: .keyboard, code: 56)
        XCTAssertEqual(hotkey.type, .keyboard)
        XCTAssertEqual(hotkey.code, 56)
    }

    func testInit_mouse() {
        let hotkey = ScrollHotkey(type: .mouse, code: 3)
        XCTAssertEqual(hotkey.type, .mouse)
        XCTAssertEqual(hotkey.code, 3)
    }

    // MARK: - legacyCode 迁移

    func testInit_legacyCode_valid() {
        let hotkey = ScrollHotkey(legacyCode: 58)
        XCTAssertNotNil(hotkey)
        XCTAssertEqual(hotkey?.type, .keyboard, "legacy codes should be keyboard type")
        XCTAssertEqual(hotkey?.code, 58)
    }

    func testInit_legacyCode_nil_returnsNil() {
        let hotkey = ScrollHotkey(legacyCode: nil)
        XCTAssertNil(hotkey)
    }

    // MARK: - Equatable

    func testEquatable_sameTypeAndCode() {
        let a = ScrollHotkey(type: .mouse, code: 5)
        let b = ScrollHotkey(type: .mouse, code: 5)
        XCTAssertEqual(a, b)
    }

    func testEquatable_differentCode() {
        let a = ScrollHotkey(type: .keyboard, code: 55)
        let b = ScrollHotkey(type: .keyboard, code: 56)
        XCTAssertNotEqual(a, b)
    }

    func testEquatable_differentType() {
        let a = ScrollHotkey(type: .keyboard, code: 5)
        let b = ScrollHotkey(type: .mouse, code: 5)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Codable

    func testCodable_roundTrip() throws {
        let original = ScrollHotkey(type: .mouse, code: 42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScrollHotkey.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodable_keyboard_roundTrip() throws {
        let original = ScrollHotkey(type: .keyboard, code: KeyCode.optionL)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScrollHotkey.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - matches (CGEvent 匹配)

    func testMatches_keyboardHotkey_matchesKeyCode() throws {
        let hotkey = ScrollHotkey(type: .keyboard, code: 56)
        // 创建一个 keyboard event
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true) else {
            throw XCTSkip("CGEvent construction failed on this environment")
        }
        let result = hotkey.matches(event, keyCode: 56, mouseButton: 0, isMouseEvent: false)
        XCTAssertTrue(result)
    }

    func testMatches_keyboardHotkey_doesNotMatchDifferentCode() throws {
        let hotkey = ScrollHotkey(type: .keyboard, code: 56)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 57, keyDown: true) else {
            throw XCTSkip("CGEvent construction failed on this environment")
        }
        let result = hotkey.matches(event, keyCode: 57, mouseButton: 0, isMouseEvent: false)
        XCTAssertFalse(result)
    }

    func testMatches_keyboardHotkey_doesNotMatchMouseEvent() throws {
        let hotkey = ScrollHotkey(type: .keyboard, code: 56)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true) else {
            throw XCTSkip("CGEvent construction failed on this environment")
        }
        let result = hotkey.matches(event, keyCode: 56, mouseButton: 3, isMouseEvent: true)
        XCTAssertFalse(result, "keyboard hotkey should not match mouse events")
    }

    func testMatches_mouseHotkey_matchesMouseButton() throws {
        let hotkey = ScrollHotkey(type: .mouse, code: 3)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center) else {
            throw XCTSkip("CGEvent construction failed on this environment")
        }
        let result = hotkey.matches(event, keyCode: 0, mouseButton: 3, isMouseEvent: true)
        XCTAssertTrue(result)
    }

    func testMatches_mouseHotkey_doesNotMatchKeyboardEvent() throws {
        let hotkey = ScrollHotkey(type: .mouse, code: 3)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 3, keyDown: true) else {
            throw XCTSkip("CGEvent construction failed on this environment")
        }
        let result = hotkey.matches(event, keyCode: 3, mouseButton: 0, isMouseEvent: false)
        XCTAssertFalse(result, "mouse hotkey should not match keyboard events")
    }

    func testMatches_mouseHotkey_doesNotMatchDifferentButton() throws {
        let hotkey = ScrollHotkey(type: .mouse, code: 3)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center) else {
            throw XCTSkip("CGEvent construction failed on this environment")
        }
        let result = hotkey.matches(event, keyCode: 0, mouseButton: 4, isMouseEvent: true)
        XCTAssertFalse(result)
    }

    // MARK: - isModifierKey

    func testIsModifierKey_shiftL_isTrue() {
        let hotkey = ScrollHotkey(type: .keyboard, code: KeyCode.shiftL)
        XCTAssertTrue(hotkey.isModifierKey)
    }

    func testIsModifierKey_commandL_isTrue() {
        let hotkey = ScrollHotkey(type: .keyboard, code: KeyCode.commandL)
        XCTAssertTrue(hotkey.isModifierKey)
    }

    func testIsModifierKey_optionL_isTrue() {
        let hotkey = ScrollHotkey(type: .keyboard, code: KeyCode.optionL)
        XCTAssertTrue(hotkey.isModifierKey)
    }

    func testIsModifierKey_regularKey_isFalse() {
        // 'a' key = 0
        let hotkey = ScrollHotkey(type: .keyboard, code: 0)
        XCTAssertFalse(hotkey.isModifierKey)
    }

    func testIsModifierKey_mouseType_isFalse() {
        // 鼠标类型不能是修饰键
        let hotkey = ScrollHotkey(type: .mouse, code: KeyCode.shiftL)
        XCTAssertFalse(hotkey.isModifierKey, "mouse type should never be a modifier key")
    }

    // MARK: - displayName

    func testDisplayName_knownKeyboard() {
        let hotkey = ScrollHotkey(type: .keyboard, code: KeyCode.shiftL)
        let name = hotkey.displayName
        XCTAssertFalse(name.isEmpty, "known keyboard key should have a display name")
        XCTAssertFalse(name.hasPrefix("Key "), "known key should not use fallback format")
    }

    func testDisplayName_unknownKeyboard() {
        let hotkey = ScrollHotkey(type: .keyboard, code: 255)
        let name = hotkey.displayName
        // 未知键会使用 "Key X" 格式
        XCTAssertTrue(name.hasPrefix("Key ") || !name.isEmpty, "unknown key should still produce a name")
    }

    func testDisplayName_knownMouse() {
        let hotkey = ScrollHotkey(type: .mouse, code: 2)
        let name = hotkey.displayName
        XCTAssertFalse(name.isEmpty, "mouse button should have a display name")
    }

    // MARK: - 默认热键配置匹配

    func testDefaultHotkeys_areKeyboardType() {
        let defaults = OPTIONS_SCROLL_DEFAULT()
        XCTAssertEqual(defaults.dash?.type, .keyboard)
        XCTAssertEqual(defaults.dash?.code, KeyCode.optionL)
        XCTAssertEqual(defaults.toggle?.type, .keyboard)
        XCTAssertEqual(defaults.toggle?.code, KeyCode.shiftL)
        XCTAssertEqual(defaults.block?.type, .keyboard)
        XCTAssertEqual(defaults.block?.code, KeyCode.commandL)
    }

    // MARK: - matchesModifierKeyCode (左右修饰键视为同一热键, #840)

    func testMatchesModifierKeyCode_leftShiftHotkey_matchesBothSides() {
        let hotkey = ScrollHotkey(type: .keyboard, code: KeyCode.shiftL)
        XCTAssertTrue(hotkey.matchesModifierKeyCode(KeyCode.shiftL))
        XCTAssertTrue(hotkey.matchesModifierKeyCode(KeyCode.shiftR), "right Shift should trigger a Shift hotkey")
    }

    func testMatchesModifierKeyCode_rightCommandHotkey_matchesLeftCommand() {
        let hotkey = ScrollHotkey(type: .keyboard, code: KeyCode.commandR)
        XCTAssertTrue(hotkey.matchesModifierKeyCode(KeyCode.commandL))
        XCTAssertTrue(hotkey.matchesModifierKeyCode(KeyCode.commandR))
    }

    func testMatchesModifierKeyCode_allModifierFamilies_matchBothSides() {
        let pairs: [(UInt16, UInt16)] = [
            (KeyCode.controlL, KeyCode.controlR),
            (KeyCode.optionL, KeyCode.optionR),
            (KeyCode.commandL, KeyCode.commandR),
            (KeyCode.shiftL, KeyCode.shiftR),
            (KeyCode.fnL, KeyCode.fnR),
        ]
        for (left, right) in pairs {
            XCTAssertTrue(ScrollHotkey(type: .keyboard, code: left).matchesModifierKeyCode(right), "\(left) should match \(right)")
            XCTAssertTrue(ScrollHotkey(type: .keyboard, code: right).matchesModifierKeyCode(left), "\(right) should match \(left)")
        }
    }

    func testMatchesModifierKeyCode_differentModifierFamily_doesNotMatch() {
        let hotkey = ScrollHotkey(type: .keyboard, code: KeyCode.shiftL)
        XCTAssertFalse(hotkey.matchesModifierKeyCode(KeyCode.commandR))
        XCTAssertFalse(hotkey.matchesModifierKeyCode(KeyCode.optionL))
    }

    func testMatchesModifierKeyCode_nonModifierKeyCode_doesNotMatch() {
        let hotkey = ScrollHotkey(type: .keyboard, code: KeyCode.shiftL)
        XCTAssertFalse(hotkey.matchesModifierKeyCode(0), "a regular key should not match a modifier hotkey")
    }

    func testMatchesModifierKeyCode_nonModifierHotkey_neverMatches() {
        XCTAssertFalse(ScrollHotkey(type: .keyboard, code: 0).matchesModifierKeyCode(0))
        XCTAssertFalse(ScrollHotkey(type: .mouse, code: KeyCode.shiftL).matchesModifierKeyCode(KeyCode.shiftL))
    }
}
