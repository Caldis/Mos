import XCTest
@testable import Mos_Debug

/// 记录端口调用的测试替身, 证明 ShortcutExecutor 经协议派发, 不依赖 ScrollCore 具体类型。
private final class FakeScrollActionPort: ScrollActionPort {
    struct Call: Equatable { let role: ScrollRole; let isDown: Bool }
    var calls: [Call] = []
    func handleMosScrollAction(role: ScrollRole, isDown: Bool) {
        calls.append(Call(role: role, isDown: isDown))
    }
}

/// 记录调用并返回固定 flags 的修饰键 provider 替身。
private final class FakeModifierFlagsProvider: ModifierFlagsProviding {
    let returnFlags: CGEventFlags
    var called = false
    init(returnFlags: CGEventFlags) { self.returnFlags = returnFlags }
    func combinedModifierFlags(physicalModifiers: CGEventFlags?) -> CGEventFlags {
        called = true
        return returnFlags
    }
}

final class ScrollActionPortTests: XCTestCase {

    private var saved: ScrollActionPort?

    override func setUp() {
        super.setUp()
        saved = ShortcutExecutor.shared.scrollActionPort
    }

    override func tearDown() {
        ShortcutExecutor.shared.scrollActionPort = saved
        super.tearDown()
    }

    func testMosScrollAction_dispatchesToInjectedPort() {
        let fake = FakeScrollActionPort()
        ShortcutExecutor.shared.scrollActionPort = fake

        guard let action = ShortcutExecutor.shared.resolveAction(named: "mosScrollDash") else {
            return XCTFail("mosScrollDash 应可解析")
        }
        _ = ShortcutExecutor.shared.execute(action: action, phase: .down)
        _ = ShortcutExecutor.shared.execute(action: action, phase: .up)

        XCTAssertEqual(fake.calls, [
            .init(role: .dash, isDown: true),
            .init(role: .dash, isDown: false)
        ])
    }

    func testCustomMouseButton_usesInjectedModifierFlagsProvider() {
        let fake = FakeModifierFlagsProvider(returnFlags: .maskShift)
        let savedProvider = ShortcutExecutor.shared.modifierFlagsProvider
        ShortcutExecutor.shared.modifierFlagsProvider = fake
        var capturedFlags: CGEventFlags?
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            capturedFlags = event.flags
        }
        defer {
            ShortcutExecutor.shared.modifierFlagsProvider = savedProvider
            ShortcutExecutor.shared.clearTestingMouseEventObserver()
        }

        // mouseMiddleClick → .mouseButton(.middle) → executeMouseButton, 合成事件时取 modifierFlagsProvider
        guard let action = ShortcutExecutor.shared.resolveAction(named: "mouseMiddleClick") else {
            return XCTFail("mouseMiddleClick 应解析为 mouseButton")
        }
        _ = ShortcutExecutor.shared.execute(action: action, phase: .down)

        XCTAssertTrue(fake.called, "executor 应调用注入的 modifierFlagsProvider")
        XCTAssertEqual(capturedFlags, .maskShift, "合成事件 flags 应取自注入 provider 的返回值")
    }
}
