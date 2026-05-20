import XCTest
@testable import Mos_Debug

final class InputPipelineProfilerTests: XCTestCase {

    override func tearDown() {
        InputPipelineProfiler.shared.resetForTesting()
        super.tearDown()
    }

    func testDisabledProfilerDoesNotCreateProbe() {
        InputPipelineProfiler.shared.configureForTesting(enabled: false)

        let probe = InputPipelineProfiler.shared.begin(
            .inputProcessor,
            inputEvent: InputEvent(
                type: .keyboard,
                code: 0,
                modifiers: CGEventFlags(rawValue: 0),
                phase: .down,
                source: .hidPP,
                device: nil
            )
        )

        XCTAssertNil(probe)
        XCTAssertEqual(InputPipelineProfiler.shared.snapshot().stats[.inputProcessor]?.count ?? 0, 0)
    }

    func testEnabledProfilerRecordsDurationAndSlowCount() {
        var ticks: [UInt64] = [1_000, 25_001_000]
        var logs: [String] = []
        InputPipelineProfiler.shared.configureForTesting(
            enabled: true,
            slowThresholdNanos: 20_000_000,
            eventLagThresholdNanos: 100_000_000,
            summaryIntervalNanos: UInt64.max,
            clock: { ticks.removeFirst() },
            logHandler: { logs.append($0) }
        )

        let probe = InputPipelineProfiler.shared.begin(
            .inputProcessor,
            inputEvent: InputEvent(
                type: .keyboard,
                code: 0,
                modifiers: CGEventFlags(rawValue: 0),
                phase: .down,
                source: .hidPP,
                device: nil
            )
        )
        probe?.end()

        let stats = InputPipelineProfiler.shared.snapshot().stats[.inputProcessor]
        XCTAssertEqual(stats?.count, 1)
        XCTAssertEqual(stats?.slowCount, 1)
        XCTAssertEqual(stats?.maxDurationNanos, 25_000_000)
        XCTAssertTrue(logs.contains { $0.contains("stage=inputProcessor") && $0.contains("durationMs=25.000") })
    }

    func testProfilerRecordsEventLagForCGEvent() throws {
        var ticks: [UInt64] = [200_000_000, 205_000_000]
        InputPipelineProfiler.shared.configureForTesting(
            enabled: true,
            slowThresholdNanos: 20_000_000,
            eventLagThresholdNanos: 100_000_000,
            summaryIntervalNanos: UInt64.max,
            clock: { ticks.removeFirst() },
            logHandler: { _ in }
        )
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        event.timestamp = 50_000_000

        let probe = InputPipelineProfiler.shared.begin(.buttonEventTap, event: event)
        probe?.end()

        let stats = InputPipelineProfiler.shared.snapshot().stats[.buttonEventTap]
        XCTAssertEqual(stats?.count, 1)
        XCTAssertEqual(stats?.eventLagSlowCount, 1)
        XCTAssertEqual(stats?.maxEventLagNanos, 150_000_000)
    }

    func testProfilerRecordsQueueWaitForAsyncStage() {
        var ticks: [UInt64] = [10_000_000, 55_000_000, 60_000_000]
        var logs: [String] = []
        InputPipelineProfiler.shared.configureForTesting(
            enabled: true,
            slowThresholdNanos: 20_000_000,
            eventLagThresholdNanos: 20_000_000,
            summaryIntervalNanos: UInt64.max,
            clock: { ticks.removeFirst() },
            logHandler: { logs.append($0) }
        )

        let queueWaitStartNanos = InputPipelineProfiler.shared.markQueueWaitStart()
        let probe = InputPipelineProfiler.shared.begin(
            .scrollDispatchPost,
            queueWaitStartNanos: queueWaitStartNanos
        )
        probe?.end()

        let stats = InputPipelineProfiler.shared.snapshot().stats[.scrollDispatchPost]
        XCTAssertEqual(stats?.count, 1)
        XCTAssertEqual(stats?.slowCount, 0)
        XCTAssertEqual(stats?.eventLagSlowCount, 1)
        XCTAssertEqual(stats?.maxEventLagNanos, 45_000_000)
        XCTAssertTrue(logs.contains { $0.contains("stage=scrollDispatchPost") && $0.contains("queueWaitMs=45.000") })
    }

    func testProfilerMeasuresSynchronousOperationWithResultMetadata() {
        var ticks: [UInt64] = [1_000_000, 36_000_000]
        var logs: [String] = []
        InputPipelineProfiler.shared.configureForTesting(
            enabled: true,
            slowThresholdNanos: 20_000_000,
            eventLagThresholdNanos: 100_000_000,
            summaryIntervalNanos: UInt64.max,
            clock: { ticks.removeFirst() },
            logHandler: { logs.append($0) }
        )

        let result = InputPipelineProfiler.shared.measure(
            .hidReportSend,
            metadata: { result in "source=hidPP type=setReport result=\(result)" }
        ) {
            7
        }

        XCTAssertEqual(result, 7)
        let stats = InputPipelineProfiler.shared.snapshot().stats[.hidReportSend]
        XCTAssertEqual(stats?.count, 1)
        XCTAssertEqual(stats?.slowCount, 1)
        XCTAssertEqual(stats?.maxDurationNanos, 35_000_000)
        XCTAssertTrue(logs.contains {
            $0.contains("stage=hidReportSend") &&
                $0.contains("durationMs=35.000") &&
                $0.contains("source=hidPP type=setReport result=7") &&
                $0.contains("thread=")
        })
    }

    func testProfilerRecordsObservedDurationForMainRunLoopHeartbeat() {
        var ticks: [UInt64] = [2_000_000_000]
        var logs: [String] = []
        InputPipelineProfiler.shared.configureForTesting(
            enabled: true,
            slowThresholdNanos: 20_000_000,
            eventLagThresholdNanos: 100_000_000,
            summaryIntervalNanos: UInt64.max,
            clock: { ticks.removeFirst() },
            logHandler: { logs.append($0) }
        )

        InputPipelineProfiler.shared.recordObservedDuration(
            .mainRunLoopHeartbeat,
            durationNanos: 150_000_000,
            metadata: "source=mainRunLoop type=heartbeat"
        )

        let stats = InputPipelineProfiler.shared.snapshot().stats[.mainRunLoopHeartbeat]
        XCTAssertEqual(stats?.count, 1)
        XCTAssertEqual(stats?.slowCount, 1)
        XCTAssertEqual(stats?.maxDurationNanos, 150_000_000)
        XCTAssertTrue(logs.contains {
            $0.contains("stage=mainRunLoopHeartbeat") &&
                $0.contains("durationMs=150.000") &&
                $0.contains("source=mainRunLoop type=heartbeat")
        })
    }

    func testSlowLogsAreRateLimitedAndDroppedCountAppearsInSummary() {
        var ticks: [UInt64] = [
            0, 25_000_000,
            30_000_000, 55_000_000,
            60_000_000, 85_000_000,
            90_000_000, 115_000_000,
            120_000_000, 145_000_000,
            150_000_000, 1_100_000_000
        ]
        var logs: [String] = []
        InputPipelineProfiler.shared.configureForTesting(
            enabled: true,
            slowThresholdNanos: 20_000_000,
            eventLagThresholdNanos: 100_000_000,
            summaryIntervalNanos: 1_000_000_000,
            slowLogLimitPerInterval: 2,
            slowLogIntervalNanos: 1_000_000_000,
            clock: { ticks.removeFirst() },
            logHandler: { logs.append($0) }
        )

        for _ in 0..<6 {
            let probe = InputPipelineProfiler.shared.begin(.inputProcessor)
            probe?.end()
        }

        let slowLogs = logs.filter { $0.contains("[InputPipelineProfiler] slow") }
        XCTAssertEqual(slowLogs.count, 2)
        XCTAssertTrue(logs.contains { $0.contains("slowLogDropped=4") })
    }

    func testSummaryContainsParseableSessionUptimeWindowAndIntervalStats() {
        var ticks: [UInt64] = [
            0, 5_000_000,
            100_000_000, 105_000_000,
            150_000_000, 160_000_000,
            220_000_000, 230_000_000
        ]
        var logs: [String] = []
        InputPipelineProfiler.shared.configureForTesting(
            enabled: true,
            slowThresholdNanos: 20_000_000,
            eventLagThresholdNanos: 100_000_000,
            summaryIntervalNanos: 100_000_000,
            clock: { ticks.removeFirst() },
            logHandler: { logs.append($0) }
        )

        for _ in 0..<4 {
            let probe = InputPipelineProfiler.shared.begin(.inputProcessor)
            probe?.end()
        }

        let summaries = logs.filter { $0.contains("[InputPipelineProfiler] summary") }
        XCTAssertEqual(summaries.count, 2)
        let secondSummary = summaries[1]
        XCTAssertTrue(secondSummary.contains("sessionId="))
        XCTAssertTrue(secondSummary.contains("uptimeSeconds=0.230"))
        XCTAssertTrue(secondSummary.contains("windowSeconds=0.125"))
        XCTAssertTrue(secondSummary.contains("stage=inputProcessor"))
        XCTAssertTrue(secondSummary.contains("intervalCount=2"))
        XCTAssertTrue(secondSummary.contains("intervalAvgMs=10.000"))
        XCTAssertTrue(secondSummary.contains("totalCount=4"))
        XCTAssertTrue(secondSummary.contains("totalAvgMs=7.500"))
        XCTAssertTrue(secondSummary.contains("slowLogDropped=0"))
    }

    func testLifecycleEventsOnlyLogWhenProfilerIsEnabled() {
        var logs: [String] = []
        InputPipelineProfiler.shared.configureForTesting(
            enabled: false,
            clock: { 1_000_000_000 },
            logHandler: { logs.append($0) }
        )

        InputPipelineProfiler.shared.recordLifecycleEvent("didWake")
        XCTAssertTrue(logs.isEmpty)

        InputPipelineProfiler.shared.configureForTesting(
            enabled: true,
            clock: { 2_000_000_000 },
            logHandler: { logs.append($0) }
        )

        InputPipelineProfiler.shared.recordLifecycleEvent("didWake")
        XCTAssertTrue(logs.contains {
            $0.contains("[InputPipelineProfiler] lifecycle") &&
                $0.contains("sessionId=") &&
                $0.contains("event=didWake") &&
                $0.contains("uptimeSeconds=2.000")
        })
    }
}
