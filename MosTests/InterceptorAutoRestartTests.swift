import XCTest
@testable import Mos_Debug

/// Interceptor keeper 自动重启退避的纯函数测试.
/// 场景背景: 主线程被 TCC 权限弹窗阻塞时, active tap 被系统超时禁用后输入才恢复;
/// keeper 盲目重启会再次冻结输入, 形成用户点不到弹窗的自锁. 冷却窗口用于打破该循环.
final class InterceptorAutoRestartTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func secondsAgo(_ s: TimeInterval) -> Date {
        return now.addingTimeInterval(-s)
    }

    func testNotThrottled_whenHistoryEmpty() {
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: [], now: now))
    }

    func testNotThrottled_belowLimitWithinWindow() {
        let history = [secondsAgo(10), secondsAgo(20)]
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: history, now: now))
    }

    func testThrottled_atLimitWithinWindow() {
        let history = [secondsAgo(5), secondsAgo(15), secondsAgo(30)]
        XCTAssertTrue(Interceptor.isAutoRestartThrottled(history: history, now: now))
    }

    func testNotThrottled_whenOldEntriesFallOutOfWindow() {
        // 两条已滑出 60s 窗口, 窗口内只剩 1 条 → 放行
        let history = [
            secondsAgo(Interceptor.autoRestartWindow + 1),
            secondsAgo(Interceptor.autoRestartWindow + 30),
            secondsAgo(10),
        ]
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: history, now: now))
    }

    func testThrottled_recoversAfterCoolDown() {
        // 冷却前: 3 条都在窗口内 → 拒绝
        let history = [secondsAgo(50), secondsAgo(55), secondsAgo(58)]
        XCTAssertTrue(Interceptor.isAutoRestartThrottled(history: history, now: now))
        // 冷却后: 同一批记录在 61s 后全部滑出窗口 → 恢复
        let later = now.addingTimeInterval(61)
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: history, now: later))
    }
}
