//
//  ScrollDispatchContextTests.swift
//  MosTests
//
//  ScrollDispatchContext generation/TTL/并发测试 (Task 7)
//

import XCTest
@testable import Mos_Debug

final class ScrollDispatchContextTests: XCTestCase {

    var sut: ScrollDispatchContext!

    override func setUp() {
        super.setUp()
        sut = ScrollDispatchContext()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - 辅助: 创建 CGEvent

    private func makeScrollEvent() -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            return nil
        }
        // preparePostingSnapshot() 要求 targetPID != 0, 合成事件默认为 0, 需手动设置
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(ProcessInfo.processInfo.processIdentifier))
        return event
    }

    // MARK: - capture

    func testDockPostingUsesLivePointerPositionWithoutChangingCapturedTemplate() throws {
        let input = try XCTUnwrap(makeScrollEvent())
        input.location = CGPoint(x: 350, y: 420)
        sut.capture(event: input, targetIsDock: true)
        let firstFrame = try XCTUnwrap(sut.preparePostingSnapshot())
        let secondFrame = try XCTUnwrap(sut.preparePostingSnapshot())

        // Both frames were captured before the pointer moved. Each must use the
        // position at actual delivery time, including the momentum tail.
        let first = try XCTUnwrap(firstFrame.eventForPosting(currentPointerLocation: {
            CGPoint(x: 400, y: 450)
        }))
        let second = try XCTUnwrap(secondFrame.eventForPosting(currentPointerLocation: {
            CGPoint(x: 500, y: 550)
        }))
        XCTAssertEqual(first.location, CGPoint(x: 400, y: 450))
        XCTAssertEqual(second.location, CGPoint(x: 500, y: 550))
        XCTAssertEqual(input.location, CGPoint(x: 350, y: 420))
        XCTAssertEqual(try XCTUnwrap(sut.preparePostingSnapshot()).event.location, input.location)
    }

    func testOtherAppsKeepOriginalLocationWithoutQueryingPointer() throws {
        let input = try XCTUnwrap(makeScrollEvent())
        input.location = CGPoint(x: 350, y: 420)
        sut.capture(event: input)
        let frame = try XCTUnwrap(sut.preparePostingSnapshot())
        let posted = try XCTUnwrap(frame.eventForPosting(currentPointerLocation: {
            XCTFail("Direct-PID posting should not query or follow the live pointer")
            return CGPoint(x: 900, y: 900)
        }))
        XCTAssertEqual(posted.location, input.location)
    }

    func testQueuedDockFrameKeepsItsRouteWhenNextInputTargetsAnotherApp() throws {
        let dockEvent = try XCTUnwrap(makeScrollEvent())
        dockEvent.location = CGPoint(x: 350, y: 420)
        sut.capture(event: dockEvent, targetIsDock: true)
        let dockFrame = try XCTUnwrap(sut.preparePostingSnapshot())

        let appEvent = try XCTUnwrap(makeScrollEvent())
        appEvent.location = CGPoint(x: 700, y: 800)
        sut.capture(event: appEvent)
        let appFrame = try XCTUnwrap(sut.preparePostingSnapshot())

        XCTAssertTrue(dockFrame.targetIsDock)
        XCTAssertEqual(dockFrame.event.location, CGPoint(x: 350, y: 420))
        XCTAssertFalse(appFrame.targetIsDock)
        XCTAssertEqual(appFrame.event.location, CGPoint(x: 700, y: 800))
    }

    func testCapture_withValidEvent_returnsTrue() throws {
        let event = try XCTUnwrap(makeScrollEvent(), "CGEvent construction failed; skipping on this environment")
        let result = sut.capture(event: event)
        XCTAssertTrue(result)
    }

    func testCapture_enablesPreparePostingSnapshot() throws {
        let event = try XCTUnwrap(makeScrollEvent())
        sut.capture(event: event)
        let snapshot = sut.preparePostingSnapshot()
        XCTAssertNotNil(snapshot, "after capture, snapshot should be available")
    }

    // MARK: - preparePostingSnapshot: 无 capture 时

    func testPreparePostingSnapshot_withoutCapture_returnsNil() {
        let snapshot = sut.preparePostingSnapshot()
        XCTAssertNil(snapshot, "without capture, snapshot should be nil")
    }

    // MARK: - advanceGeneration

    func testAdvanceGeneration_incrementsGeneration() throws {
        let event = try XCTUnwrap(makeScrollEvent())
        sut.capture(event: event)
        let snap1 = sut.preparePostingSnapshot()
        let gen1 = snap1?.generation ?? 0

        sut.advanceGeneration()

        let snap2 = sut.preparePostingSnapshot()
        let gen2 = snap2?.generation ?? 0

        XCTAssertEqual(gen2, gen1 + 1, "advanceGeneration should increment by 1")
    }

    // MARK: - clearContext

    func testClearContext_removesTemplate() throws {
        let event = try XCTUnwrap(makeScrollEvent())
        sut.capture(event: event)
        XCTAssertNotNil(sut.preparePostingSnapshot())

        sut.clearContext()
        XCTAssertNil(sut.preparePostingSnapshot(), "after clearContext, snapshot should be nil")
    }

    // MARK: - invalidateAll

    func testInvalidateAll_clearsAndAdvancesGeneration() throws {
        let event = try XCTUnwrap(makeScrollEvent())
        sut.capture(event: event)
        let snap1 = sut.preparePostingSnapshot()
        let gen1 = snap1?.generation ?? 0

        sut.invalidateAll()

        // Template cleared
        XCTAssertNil(sut.preparePostingSnapshot(), "after invalidateAll, template should be nil")

        // Re-capture to check generation
        sut.capture(event: event)
        let snap2 = sut.preparePostingSnapshot()
        XCTAssertNotNil(snap2)
        XCTAssertGreaterThan(snap2!.generation, gen1, "generation should have advanced")
    }

    // MARK: - PostingSnapshot: generation 匹配

    func testEnqueue_dropsSnapshot_whenGenerationMismatch() throws {
        let event = try XCTUnwrap(makeScrollEvent())
        sut.capture(event: event)
        let snapshot = try XCTUnwrap(sut.preparePostingSnapshot())

        // 推进 generation, 使快照过时
        sut.advanceGeneration()

        // enqueue 异步执行, 使用 expectation 等待
        let exp = expectation(description: "enqueue completes")
        sut.resetDiagnostics()

        sut.enqueue(snapshot)

        // 给 postQueue 足够时间处理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let diag = sut.diagnosticsSnapshot()
        XCTAssertEqual(diag.droppedFramesByGeneration, 1, "stale generation should be dropped")
        XCTAssertEqual(diag.postedFrames, 0, "stale frame should not be posted")
    }

    // MARK: - PostingSnapshot: TTL 过期

    func testEnqueue_dropsSnapshot_whenTTLExpired() throws {
        let event = try XCTUnwrap(makeScrollEvent())

        // 设置非常短的 TTL
        sut.eventTTL = 0.0

        sut.capture(event: event)
        let snapshot = try XCTUnwrap(sut.preparePostingSnapshot())

        // 等待 TTL 过期
        Thread.sleep(forTimeInterval: 0.01)

        sut.resetDiagnostics()

        let exp = expectation(description: "enqueue completes")
        sut.enqueue(snapshot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let diag = sut.diagnosticsSnapshot()
        XCTAssertEqual(diag.droppedFramesByTTL, 1, "expired TTL should be dropped")
    }

    // MARK: - 并发安全: 多线程 capture + advanceGeneration

    func testConcurrentCaptureAndAdvance_doesNotCrash() throws {
        let event = try XCTUnwrap(makeScrollEvent())
        let iterations = 1000

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for _ in 0..<iterations {
            group.enter()
            queue.async {
                self.sut.capture(event: event)
                group.leave()
            }

            group.enter()
            queue.async {
                self.sut.advanceGeneration()
                group.leave()
            }

            group.enter()
            queue.async {
                _ = self.sut.preparePostingSnapshot()
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "concurrent operations should complete without deadlock")
    }

    // MARK: - 并发安全: 多线程 invalidateAll

    func testConcurrentInvalidateAll_doesNotCrash() throws {
        let event = try XCTUnwrap(makeScrollEvent())
        let iterations = 500

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent.invalidate", attributes: .concurrent)

        for _ in 0..<iterations {
            group.enter()
            queue.async {
                self.sut.capture(event: event)
                group.leave()
            }

            group.enter()
            queue.async {
                self.sut.invalidateAll()
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "concurrent invalidateAll should complete without deadlock")
    }

    // MARK: - diagnostics

    func testDiagnostics_initiallyAllZero() {
        sut.resetDiagnostics()
        let diag = sut.diagnosticsSnapshot()
        XCTAssertEqual(diag.postedFrames, 0)
        XCTAssertEqual(diag.droppedFramesByGeneration, 0)
        XCTAssertEqual(diag.droppedFramesByTTL, 0)
        XCTAssertEqual(diag.skippedSyntheticEvents, 0)
        XCTAssertEqual(diag.updateSnapshotFailures, 0)
    }

    func testRecordSkippedSyntheticEvent_increments() {
        sut.resetDiagnostics()
        sut.recordSkippedSyntheticEvent()
        sut.recordSkippedSyntheticEvent()
        let diag = sut.diagnosticsSnapshot()
        XCTAssertEqual(diag.skippedSyntheticEvents, 2)
    }

    func testResetDiagnostics_clearsAll() {
        sut.recordSkippedSyntheticEvent()
        sut.resetDiagnostics()
        let diag = sut.diagnosticsSnapshot()
        XCTAssertEqual(diag.skippedSyntheticEvents, 0)
        XCTAssertEqual(diag.postedFrames, 0)
    }

    // MARK: - snapshot 独立性

    func testPreparePostingSnapshot_returnsIndependentCopies() throws {
        let event = try XCTUnwrap(makeScrollEvent())
        sut.capture(event: event)

        let snap1 = sut.preparePostingSnapshot()
        let snap2 = sut.preparePostingSnapshot()

        XCTAssertNotNil(snap1)
        XCTAssertNotNil(snap2)
        // 两个快照应该有不同的 event 对象 (独立 copy)
        // 无法直接比较 CGEvent 身份 (是 CFType), 但 generation 应相同
        XCTAssertEqual(snap1?.generation, snap2?.generation)
        XCTAssertEqual(snap1?.targetPID, snap2?.targetPID)
    }
}
