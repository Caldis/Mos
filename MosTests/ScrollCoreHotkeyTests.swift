//
//  ScrollCoreHotkeyTests.swift
//  MosTests
//
//  ScrollCore.handleScrollHotkey 热键匹配测试 (Task 9)
//
//  注意: 这些测试直接操作 ScrollCore.shared 的热键状态,
//  由于 handleScrollHotkey 内部会调用 ScrollUtils.shared 和
//  NSWorkspace 来获取热键配置, 在 CI 环境中配置可能为 nil。
//  因此仅测试 key-up 释放逻辑 (不依赖热键配置) 和基本返回值。
//

import XCTest
@testable import Mos_Debug

final class ScrollCoreHotkeyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 重置 ScrollCore 热键状态
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
    }

    override func tearDown() {
        // 清理状态
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
        super.tearDown()
    }

    // MARK: - key-up: 无已激活状态时

    func testKeyUp_withNoHeldCodes_returnsFalse() {
        let result = ScrollCore.shared.handleScrollHotkey(code: 42, isDown: false)
        XCTAssertFalse(result, "key-up with no held codes should return false")
    }

    // MARK: - key-up: 释放已跟踪的 code

    func testKeyUp_releasesTrackedDashCode() {
        // 模拟 dash 已被 HID++ 按下
        ScrollCore.shared.dashScroll = true
        ScrollCore.shared.dashAmplification = 5.0
        ScrollCore.shared.dashKeyHeld = true

        // 直接设置私有的 hidDashHeldCode (通过模拟一次完整的 down-up)
        // 由于 hidDashHeldCode 是 private, 我们需要通过正常的 key-down 路径设置
        // 但 key-down 依赖 Options 配置, 所以这里测试 key-up 对不匹配的 code 不会误清除
        let result = ScrollCore.shared.handleScrollHotkey(code: 999, isDown: false)
        XCTAssertFalse(result, "key-up with non-matching code should return false")

        // 验证状态没有被错误清除
        XCTAssertTrue(ScrollCore.shared.dashScroll, "dashScroll should not be cleared by non-matching key-up")
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 5.0, "dashAmplification should not be cleared")
    }

    // MARK: - key-down: 无热键配置时

    func testKeyDown_withNoHotkeyConfig_returnsFalse() {
        // 在没有配置 HID++ 鼠标按键热键时 (默认热键是键盘修饰键),
        // mouse type 的 code 不会匹配, 应返回 false
        // 默认: dash=optionL(keyboard), toggle=shiftL(keyboard), block=commandL(keyboard)
        let result = ScrollCore.shared.handleScrollHotkey(code: 100, isDown: true)
        // 由于默认热键是 keyboard 类型, 而 HID++ 匹配要求 type == .mouse,
        // 所以不会匹配
        XCTAssertFalse(result, "keyboard-type hotkey should not match mouse code from HID++")
    }

    // MARK: - key-down 后 key-up 完整流程 (需要配置 mouse 类型热键)

    func testKeyDown_thenKeyUp_withMouseHotkey() {
        // 临时配置 dash 热键为 mouse 按键 code=50
        let originalDash = Options.shared.scroll.dash
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        defer { Options.shared.scroll.dash = originalDash }

        // key-down
        let downResult = ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true)
        XCTAssertTrue(downResult, "mouse hotkey matching code should return true on key-down")
        XCTAssertTrue(ScrollCore.shared.dashScroll, "dashScroll should be set on key-down")
        XCTAssertTrue(ScrollCore.shared.dashKeyHeld, "dashKeyHeld should be set")
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 5.0, "dashAmplification should be 5.0")

        // key-up
        let upResult = ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertTrue(upResult, "key-up of tracked code should return true")
        XCTAssertFalse(ScrollCore.shared.dashScroll, "dashScroll should be cleared on key-up")
        XCTAssertFalse(ScrollCore.shared.dashKeyHeld, "dashKeyHeld should be cleared")
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0, "dashAmplification should reset to 1.0")
    }

    func testKeyDown_thenKeyUp_toggleHotkey() {
        let originalToggle = Options.shared.scroll.toggle
        Options.shared.scroll.toggle = ScrollHotkey(type: .mouse, code: 60)
        defer { Options.shared.scroll.toggle = originalToggle }

        let downResult = ScrollCore.shared.handleScrollHotkey(code: 60, isDown: true)
        XCTAssertTrue(downResult)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.toggleKeyHeld)

        let upResult = ScrollCore.shared.handleScrollHotkey(code: 60, isDown: false)
        XCTAssertTrue(upResult)
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
        XCTAssertFalse(ScrollCore.shared.toggleKeyHeld)
    }

    func testKeyDown_thenKeyUp_blockHotkey() {
        let originalBlock = Options.shared.scroll.block
        Options.shared.scroll.block = ScrollHotkey(type: .mouse, code: 70)
        defer { Options.shared.scroll.block = originalBlock }

        let downResult = ScrollCore.shared.handleScrollHotkey(code: 70, isDown: true)
        XCTAssertTrue(downResult)
        XCTAssertTrue(ScrollCore.shared.blockSmooth)
        XCTAssertTrue(ScrollCore.shared.blockKeyHeld)

        let upResult = ScrollCore.shared.handleScrollHotkey(code: 70, isDown: false)
        XCTAssertTrue(upResult)
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
        XCTAssertFalse(ScrollCore.shared.blockKeyHeld)
    }

    // MARK: - 多个热键同时按下

    func testMultipleHotkeys_simultaneouslyPressed() {
        let originalDash = Options.shared.scroll.dash
        let originalToggle = Options.shared.scroll.toggle
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        Options.shared.scroll.toggle = ScrollHotkey(type: .mouse, code: 60)
        defer {
            Options.shared.scroll.dash = originalDash
            Options.shared.scroll.toggle = originalToggle
        }

        // 按下 dash
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        // 同时按下 toggle
        ScrollCore.shared.handleScrollHotkey(code: 60, isDown: true)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.dashScroll, "dash should still be active")

        // 释放 dash
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertFalse(ScrollCore.shared.dashScroll, "dash should be released")
        XCTAssertTrue(ScrollCore.shared.toggleScroll, "toggle should still be active")

        // 释放 toggle
        ScrollCore.shared.handleScrollHotkey(code: 60, isDown: false)
        XCTAssertFalse(ScrollCore.shared.toggleScroll, "toggle should be released")
    }

    // MARK: - key-up 不依赖当前 app 配置 (防止焦点切换状态卡死)

    func testKeyUp_releasesRegardlessOfCurrentConfig() {
        // 配置 dash 为 mouse code=50 并按下
        let originalDash = Options.shared.scroll.dash
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        // 改变配置 (模拟焦点切换到不同 app)
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 999)

        // key-up 仍然应该按照跟踪的 code 释放
        let upResult = ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertTrue(upResult, "key-up should release by tracked code, not current config")
        XCTAssertFalse(ScrollCore.shared.dashScroll)

        Options.shared.scroll.dash = originalDash
    }

    // MARK: - 同一 code 配置给多个热键

    func testSameCode_matchesAllConfiguredHotkeys() {
        let originalDash = Options.shared.scroll.dash
        let originalToggle = Options.shared.scroll.toggle
        let originalBlock = Options.shared.scroll.block
        // 配置所有热键为同一 code
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 80)
        Options.shared.scroll.toggle = ScrollHotkey(type: .mouse, code: 80)
        Options.shared.scroll.block = ScrollHotkey(type: .mouse, code: 80)
        defer {
            Options.shared.scroll.dash = originalDash
            Options.shared.scroll.toggle = originalToggle
            Options.shared.scroll.block = originalBlock
        }

        let downResult = ScrollCore.shared.handleScrollHotkey(code: 80, isDown: true)
        XCTAssertTrue(downResult)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.blockSmooth)

        let upResult = ScrollCore.shared.handleScrollHotkey(code: 80, isDown: false)
        XCTAssertTrue(upResult)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
    }
}
