import XCTest
@testable import Mos_Debug

final class OptionsChangePropagationTests: XCTestCase {

    /// 订阅只对命中的组触发
    func testObserveFiresForMatchingGroupOnly() {
        let options = Options()
        var received: [OptionsGroup] = []
        options.observe([.scroll]) { received.append($0) }
        options.markChanged(.scroll)
        options.markChanged(.buttons)
        XCTAssertEqual(received, [.scroll])
    }

    /// scroll 容器身份路由: 自身的 scroll → .scroll, 其他实例 (per-app) → .application
    func testScrollContainerIdentityRouting() {
        let options = Options()
        var received: [OptionsGroup] = []
        options.observe([.scroll, .application]) { received.append($0) }
        options.markChanged(scrollContainer: options.scroll)
        options.markChanged(scrollContainer: OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(received, [.scroll, .application])
    }

    /// buttons 容器身份路由
    func testButtonsContainerIdentityRouting() {
        let options = Options()
        var received: [OptionsGroup] = []
        options.observe([.buttons, .application]) { received.append($0) }
        options.markChanged(buttonsContainer: options.buttons)
        options.markChanged(buttonsContainer: OPTIONS_BUTTONS_DEFAULT())
        XCTAssertEqual(received, [.buttons, .application])
    }

    /// 读取期间 (readingOptionsLock) 抑制通知
    func testMarkChangedSuppressedDuringRead() {
        let options = Options()
        var fired = false
        options.observe([.scroll]) { _ in fired = true }
        options.withReadingLockForTests {
            options.markChanged(.scroll)
        }
        XCTAssertFalse(fired)
        options.markChanged(.scroll)
        XCTAssertTrue(fired)
    }

    /// 同一 runloop tick 内多次变更合并为一次 flush, 且只含脏组
    func testSameTickChangesCoalesceIntoSingleFlush() {
        let options = Options()
        let flushed = expectation(description: "flush")
        var flushedGroups: Set<OptionsGroup> = []
        var flushCount = 0
        options.onFlushForTests = { groups in
            flushedGroups = groups
            flushCount += 1
            flushed.fulfill()
        }
        options.markChanged(.scroll)
        options.markChanged(.scroll)
        options.markChanged(.buttons)
        wait(for: [flushed], timeout: 2.0)
        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(flushedGroups, [.scroll, .buttons])
    }
}
