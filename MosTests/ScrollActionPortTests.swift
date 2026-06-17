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
}
