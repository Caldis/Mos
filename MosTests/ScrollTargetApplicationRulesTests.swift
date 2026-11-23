//
//  ScrollTargetApplicationRulesTests.swift
//  MosTests
//
//  #1011 回归测试: 关闭 "继承全局设定" 后, 按应用配置的平滑/翻转
//  不应再被全局开关联动压制; 继承开启时仍与全局保持一致。
//

import XCTest
@testable import Mos_Debug

final class ScrollTargetApplicationRulesTests: XCTestCase {

    // 仅快照本测试会改动的开关 (OPTIONS_SCROLL_DEFAULT 是 class, 引用快照无法回滚变更)
    private var savedGlobalSmooth = false
    private var savedGlobalSmoothVertical = false
    private var savedGlobalSmoothHorizontal = false
    private var savedGlobalReverse = false
    private var savedGlobalReverseVertical = false
    private var savedGlobalReverseHorizontal = false

    override func setUp() {
        super.setUp()
        // 保存全局滚动开关 (XCTest 下 markChanged 不落盘, 只影响内存)
        savedGlobalSmooth = Options.shared.scroll.smooth
        savedGlobalSmoothVertical = Options.shared.scroll.smoothVertical
        savedGlobalSmoothHorizontal = Options.shared.scroll.smoothHorizontal
        savedGlobalReverse = Options.shared.scroll.reverse
        savedGlobalReverseVertical = Options.shared.scroll.reverseVertical
        savedGlobalReverseHorizontal = Options.shared.scroll.reverseHorizontal
    }

    override func tearDown() {
        // 还原全局滚动开关
        Options.shared.scroll.smooth = savedGlobalSmooth
        Options.shared.scroll.smoothVertical = savedGlobalSmoothVertical
        Options.shared.scroll.smoothHorizontal = savedGlobalSmoothHorizontal
        Options.shared.scroll.reverse = savedGlobalReverse
        Options.shared.scroll.reverseVertical = savedGlobalReverseVertical
        Options.shared.scroll.reverseHorizontal = savedGlobalReverseHorizontal
        super.tearDown()
    }

    /// 构造一个不进入持久化列表的独立 Application 对象
    private func makeApplication(inherit: Bool) -> Application {
        let application = Application(path: "/Applications/RegressionTest.app")
        application.inherit = inherit
        return application
    }

    // MARK: - #1011: 全局关闭时, 按应用开启的规则必须生效

    func testPerAppSmoothAppliesWhenGlobalSmoothOff() {
        Options.shared.scroll.smooth = false
        Options.shared.scroll.smoothVertical = false
        Options.shared.scroll.smoothHorizontal = false
        let application = makeApplication(inherit: false)
        application.scroll.smooth = true

        XCTAssertTrue(application.isSmooth(false), "per-app smooth=ON must apply when global smooth is OFF (#1011)")
        XCTAssertTrue(application.isSmoothVertical(false), "per-app axis smooth must not be gated by global axis switches")
        XCTAssertTrue(application.isSmoothHorizontal(false), "per-app axis smooth must not be gated by global axis switches")
    }

    func testPerAppReverseAppliesWhenGlobalReverseOff() {
        Options.shared.scroll.reverse = false
        Options.shared.scroll.reverseVertical = false
        Options.shared.scroll.reverseHorizontal = false
        let application = makeApplication(inherit: false)
        application.scroll.reverse = true

        XCTAssertTrue(application.isReverse(), "per-app reverse=ON must apply when global reverse is OFF (#1011)")
        XCTAssertTrue(application.isReverseVertical(), "per-app axis reverse must not be gated by global axis switches")
        XCTAssertTrue(application.isReverseHorizontal(), "per-app axis reverse must not be gated by global axis switches")
    }

    // MARK: - #1011 另一半语义: 全局开启时, 按应用关闭的规则也必须生效

    func testPerAppDisableAppliesWhenGlobalSwitchesOn() {
        Options.shared.scroll.smooth = true
        Options.shared.scroll.smoothVertical = true
        Options.shared.scroll.smoothHorizontal = true
        Options.shared.scroll.reverse = true
        Options.shared.scroll.reverseVertical = true
        Options.shared.scroll.reverseHorizontal = true
        let application = makeApplication(inherit: false)
        application.scroll.smooth = false
        application.scroll.reverse = false

        XCTAssertFalse(application.isSmooth(false), "per-app smooth=OFF must disable smoothing when global smooth is ON")
        XCTAssertFalse(application.isSmoothVertical(false), "per-app smooth=OFF must disable axis smoothing")
        XCTAssertFalse(application.isSmoothHorizontal(false), "per-app smooth=OFF must disable axis smoothing")
        XCTAssertFalse(application.isReverseVertical(), "per-app reverse=OFF must disable vertical reverse when global reverse is ON")
        XCTAssertFalse(application.isReverseHorizontal(), "per-app reverse=OFF must disable horizontal reverse when global reverse is ON")
    }

    // MARK: - 继承语义: inherit=on 时仍与全局一致

    func testInheritStillMirrorsGlobalSwitches() {
        Options.shared.scroll.smooth = false
        Options.shared.scroll.reverse = false
        let inheriting = makeApplication(inherit: true)
        XCTAssertFalse(inheriting.isSmooth(false), "inherit=ON must follow global smooth=OFF")
        XCTAssertFalse(inheriting.isReverseVertical(), "inherit=ON must follow global reverse=OFF")

        Options.shared.scroll.smooth = true
        Options.shared.scroll.reverse = true
        Options.shared.scroll.reverseVertical = true
        XCTAssertTrue(inheriting.isSmooth(false), "inherit=ON must follow global smooth=ON")
        XCTAssertTrue(inheriting.isReverseVertical(), "inherit=ON must follow global reverse=ON")
    }

    // MARK: - 独立配置内部的从属关系仍然生效

    func testOwnAxisTogglesStillGateWithinApplicationOptions() {
        Options.shared.scroll.smooth = true
        Options.shared.scroll.reverse = true
        let application = makeApplication(inherit: false)
        application.scroll.smooth = true
        application.scroll.reverse = true
        application.scroll.smoothVertical = false
        application.scroll.reverseVertical = false

        XCTAssertFalse(application.isSmoothVertical(false), "own smoothVertical=OFF must disable vertical smoothing")
        XCTAssertTrue(application.isSmoothHorizontal(false), "own smoothHorizontal default ON must stay ON")
        XCTAssertFalse(application.isReverseVertical(), "own reverseVertical=OFF must disable vertical reverse")
        XCTAssertTrue(application.isReverseHorizontal(), "own reverseHorizontal default ON must stay ON")
    }

    // MARK: - 禁用平滑热键仍然优先

    func testBlockHotkeyStillSuppressesSmooth() {
        Options.shared.scroll.smooth = true
        let application = makeApplication(inherit: false)
        application.scroll.smooth = true

        XCTAssertFalse(application.isSmooth(true), "block hotkey must suppress per-app smoothing")
        XCTAssertFalse(application.isSmoothVertical(true), "block hotkey must suppress per-app axis smoothing")
    }

    // MARK: - 匹配链: 两种添加方式保存的路径都能命中运行中应用

    func testGetTargetApplicationMatchesBothPickStyles() throws {
        let current = NSRunningApplication.current
        guard let executablePath = current.executableURL?.path,
              let bundlePath = current.bundleURL?.path else {
            throw XCTSkip("No resolvable executable/bundle path in this environment")
        }
        let applications = Options.shared.application.applications
        // 若本机配置已存在匹配宿主应用的条目, 跳过 (无法断言干净的初始状态)
        guard ScrollUtils.shared.getTargetApplication(from: current) == nil else {
            throw XCTSkip("A pre-existing applications entry matches the test host")
        }

        // 运行中应用列表添加: 保存可执行文件路径
        applications.append(Application(path: executablePath))
        defer { applications.remove(from: executablePath) }
        XCTAssertNotNil(
            ScrollUtils.shared.getTargetApplication(from: current),
            "running-app pick (executable path) must match the event-time lookup"
        )
        // 移除后再验证 Bundle 路径, 避免经由可执行路径的回退匹配误通过
        applications.remove(from: executablePath)

        // 文件面板添加: 保存 Bundle 路径
        applications.append(Application(path: bundlePath))
        defer { applications.remove(from: bundlePath) }
        XCTAssertNotNil(
            ScrollUtils.shared.getTargetApplication(from: current),
            "file-panel pick (bundle path) must match the event-time lookup"
        )
        applications.remove(from: bundlePath)

        // 未添加的其他路径不应命中
        XCTAssertNil(ScrollUtils.shared.getTargetApplication(from: current))
    }
}
