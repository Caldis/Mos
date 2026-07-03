import XCTest
@testable import Mos_Debug

/// P0-5 回归: IRoot.GetFeature 响应不回显 featureId, 并发 discovery 必须 FIFO 串行,
/// 防止 REPROG 的 featureIndex 被错配给 SmartShift 回调 (错误 index 会被持久化到缓存)
final class LogiFeatureDiscoveryQueueTests: XCTestCase {

    private let reprogFeatureId: UInt16 = 0x1B04
    private let smartShiftFeatureId: UInt16 = 0x2110

    // 队列为空时入队应立即给出待发送请求; 已有飞行中请求时应排队
    func testEnqueueReturnsSendableOnlyWhenIdle() {
        var queue = LogiDeviceSession.FeatureDiscoveryQueue()
        XCTAssertEqual(queue.enqueue(featureId: reprogFeatureId, completion: { _ in }), reprogFeatureId)
        XCTAssertNil(queue.enqueue(featureId: smartShiftFeatureId, completion: { _ in }),
                     "已有飞行中请求时后续入队不应触发发送")
        XCTAssertEqual(queue.inFlightFeatureId, reprogFeatureId)
    }

    // 核心竞态回归: REPROG discovery 未完成时并发 SmartShift discovery,
    // 两个响应必须按 FIFO 顺序各自结算到自己的回调, 不得错配
    func testConcurrentDiscoveriesSettleInFIFOOrder() {
        var queue = LogiDeviceSession.FeatureDiscoveryQueue()
        var reprogResult: UInt8? = nil
        var smartShiftResult: UInt8? = nil
        var settleOrder: [UInt16] = []

        _ = queue.enqueue(featureId: reprogFeatureId) { reprogResult = $0 }
        _ = queue.enqueue(featureId: smartShiftFeatureId) { smartShiftResult = $0 }

        // 第一个响应 (REPROG index=0x0A) 只结算队头
        let first = queue.settleHead()
        XCTAssertNotNil(first)
        settleOrder.append(reprogFeatureId)
        first?.completion(0x0A)
        XCTAssertEqual(first?.nextFeatureId, smartShiftFeatureId, "结算队头后应给出下一个待发送请求")
        XCTAssertEqual(reprogResult, 0x0A)
        XCTAssertNil(smartShiftResult, "SmartShift 回调不应收到 REPROG 的响应")

        // 第二个响应 (SmartShift index=0x05) 结算新队头
        let second = queue.settleHead()
        XCTAssertNotNil(second)
        second?.completion(0x05)
        XCTAssertNil(second?.nextFeatureId)
        XCTAssertEqual(smartShiftResult, 0x05)
        XCTAssertEqual(reprogResult, 0x0A, "REPROG 结果不应被第二个响应覆盖")
        XCTAssertTrue(queue.isIdle)
    }

    // 错误/超时只结算飞行中的队头, 排队中的请求保留待发送
    func testErrorSettlesOnlyHead() {
        var queue = LogiDeviceSession.FeatureDiscoveryQueue()
        var reprogResult: UInt8? = 0xFF
        var smartShiftCalled = false

        _ = queue.enqueue(featureId: reprogFeatureId) { reprogResult = $0 }
        _ = queue.enqueue(featureId: smartShiftFeatureId) { _ in smartShiftCalled = true }

        let settled = queue.settleHead()
        settled?.completion(nil)  // 超时/错误
        XCTAssertNil(reprogResult)
        XCTAssertFalse(smartShiftCalled, "排队中的请求不应被队头的错误连带结算")
        XCTAssertEqual(queue.inFlightFeatureId, smartShiftFeatureId)
    }

    // 静默清空 (teardown / 切 slot) 不触发任何回调
    func testClearFiresNoCallbacks() {
        var queue = LogiDeviceSession.FeatureDiscoveryQueue()
        var callbackCount = 0
        _ = queue.enqueue(featureId: reprogFeatureId) { _ in callbackCount += 1 }
        _ = queue.enqueue(featureId: smartShiftFeatureId) { _ in callbackCount += 1 }

        queue.clear()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertTrue(queue.isIdle)
        XCTAssertNil(queue.settleHead(), "清空后结算应为 no-op")
    }
}
