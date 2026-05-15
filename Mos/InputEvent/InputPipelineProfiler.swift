//
//  InputPipelineProfiler.swift
//  Mos
//
//  Created by Codex on 2026/5/15.
//

import Cocoa
import Foundation

final class InputPipelineProfiler {

    static let shared = InputPipelineProfiler()

    enum Stage: String, CaseIterable {
        case buttonEventTap
        case inputProcessor
        case buttonBindingMatch
        case scrollEventTap
        case scrollHotkeyTap
        case scrollPosterUpdate
        case scrollPosterFrame
        case scrollDispatchPost
    }

    struct StageStats: Equatable {
        private(set) var count: UInt64 = 0
        private(set) var totalDurationNanos: UInt64 = 0
        private(set) var maxDurationNanos: UInt64 = 0
        private(set) var slowCount: UInt64 = 0
        private(set) var maxEventLagNanos: UInt64 = 0
        private(set) var eventLagSlowCount: UInt64 = 0

        var averageDurationNanos: UInt64 {
            guard count > 0 else { return 0 }
            return totalDurationNanos / count
        }

        mutating func record(
            durationNanos: UInt64,
            eventLagNanos: UInt64?,
            slowThresholdNanos: UInt64,
            eventLagThresholdNanos: UInt64
        ) {
            count &+= 1
            totalDurationNanos &+= durationNanos
            maxDurationNanos = max(maxDurationNanos, durationNanos)
            if durationNanos >= slowThresholdNanos {
                slowCount &+= 1
            }
            if let eventLagNanos {
                maxEventLagNanos = max(maxEventLagNanos, eventLagNanos)
                if eventLagNanos >= eventLagThresholdNanos {
                    eventLagSlowCount &+= 1
                }
            }
        }
    }

    struct Snapshot {
        let isEnabled: Bool
        let stats: [Stage: StageStats]
    }

    struct Probe {
        fileprivate let profiler: InputPipelineProfiler
        fileprivate let stage: Stage
        fileprivate let startNanos: UInt64
        fileprivate let metadata: EventMetadata?

        func end() {
            profiler.finish(self)
        }
    }

    fileprivate struct EventMetadata {
        let source: String
        let type: String
        let code: UInt16?
        let phase: String?
        let latencyLabel: String?
        let lagNanos: UInt64?

        var description: String {
            var parts = ["source=\(source)", "type=\(type)"]
            if let code {
                parts.append("code=\(code)")
            }
            if let phase {
                parts.append("phase=\(phase)")
            }
            if let lagNanos, let latencyLabel {
                parts.append(String(format: "\(latencyLabel)=%.3f", Double(lagNanos) / 1_000_000.0))
            }
            return parts.joined(separator: " ")
        }

        func replacingLatency(label: String, nanos: UInt64) -> EventMetadata {
            EventMetadata(
                source: source,
                type: type,
                code: code,
                phase: phase,
                latencyLabel: label,
                lagNanos: nanos
            )
        }
    }

    private enum Defaults {
        static let environmentKey = "MOS_INPUT_PIPELINE_PROFILING"
        static let userDefaultsKey = "InputPipelineProfilingEnabled"
        static let slowThresholdNanos: UInt64 = 20_000_000
        static let eventLagThresholdNanos: UInt64 = 100_000_000
        static let summaryIntervalNanos: UInt64 = 60_000_000_000
        static let slowLogLimitPerInterval: UInt64 = 30
        static let slowLogIntervalNanos: UInt64 = 60_000_000_000
    }

    private struct SlowLogRateState {
        var intervalStartNanos: UInt64?
        var emittedCount: UInt64 = 0
    }

    private let lock = NSLock()
    private var enabled: Bool
    private var slowThresholdNanos: UInt64
    private var eventLagThresholdNanos: UInt64
    private var summaryIntervalNanos: UInt64
    private var slowLogLimitPerInterval: UInt64
    private var slowLogIntervalNanos: UInt64
    private var lastSummaryNanos: UInt64 = 0
    private var stats: [Stage: StageStats] = [:]
    private var intervalStats: [Stage: StageStats] = [:]
    private var slowLogRateStates: [Stage: SlowLogRateState] = [:]
    private var slowLogDropped: UInt64 = 0
    private var clock: () -> UInt64
    private var processStartNanos: UInt64
    private let sessionId: String
    private var logHandler: (String) -> Void

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) {
        let defaultClock = { DispatchTime.now().uptimeNanoseconds }
        enabled = Self.resolveEnabled(environment: environment, userDefaults: userDefaults)
        slowThresholdNanos = Defaults.slowThresholdNanos
        eventLagThresholdNanos = Defaults.eventLagThresholdNanos
        summaryIntervalNanos = Defaults.summaryIntervalNanos
        slowLogLimitPerInterval = Defaults.slowLogLimitPerInterval
        slowLogIntervalNanos = Defaults.slowLogIntervalNanos
        clock = defaultClock
        processStartNanos = defaultClock()
        lastSummaryNanos = processStartNanos
        sessionId = UUID().uuidString
        logHandler = { line in NSLog("%@", line) }
    }

    @inline(__always)
    func begin(_ stage: Stage, event: CGEvent? = nil, queueWaitStartNanos: UInt64? = nil) -> Probe? {
        guard enabled else { return nil }
        let now = clock()
        return Probe(
            profiler: self,
            stage: stage,
            startNanos: now,
            metadata: makeMetadata(event: event, now: now, queueWaitStartNanos: queueWaitStartNanos)
        )
    }

    @inline(__always)
    func begin(_ stage: Stage, inputEvent: InputEvent) -> Probe? {
        guard enabled else { return nil }
        let now = clock()
        return Probe(
            profiler: self,
            stage: stage,
            startNanos: now,
            metadata: metadata(for: inputEvent)
        )
    }

    @inline(__always)
    func markQueueWaitStart() -> UInt64? {
        guard enabled else { return nil }
        return clock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        let snapshot = Snapshot(isEnabled: enabled, stats: stats)
        lock.unlock()
        return snapshot
    }

    func logStartupConfiguration() {
        guard enabled else { return }
        let now = clock()
        logHandler(
            String(
                format: "[InputPipelineProfiler] enabled sessionId=%@ uptimeSeconds=%@ slowThresholdMs=%.3f eventLagThresholdMs=%.3f summaryIntervalSeconds=%.1f slowLogLimit=%llu slowLogIntervalSeconds=%.1f",
                sessionId,
                uptimeSecondsText(atNanos: now),
                Double(slowThresholdNanos) / 1_000_000.0,
                Double(eventLagThresholdNanos) / 1_000_000.0,
                Double(summaryIntervalNanos) / 1_000_000_000.0,
                slowLogLimitPerInterval,
                Double(slowLogIntervalNanos) / 1_000_000_000.0
            )
        )
    }

    func recordLifecycleEvent(_ event: String) {
        guard enabled else { return }
        let now = clock()

        let handler: (String) -> Void
        let uptimeNanos: UInt64
        lock.lock()
        handler = logHandler
        uptimeNanos = now >= processStartNanos ? now - processStartNanos : 0
        lock.unlock()

        handler(
            "[InputPipelineProfiler] lifecycle sessionId=\(sessionId) uptimeSeconds=\(secondsText(uptimeNanos)) event=\(event)"
        )
    }

    func configureForTesting(
        enabled: Bool,
        slowThresholdNanos: UInt64 = Defaults.slowThresholdNanos,
        eventLagThresholdNanos: UInt64 = Defaults.eventLagThresholdNanos,
        summaryIntervalNanos: UInt64 = Defaults.summaryIntervalNanos,
        slowLogLimitPerInterval: UInt64 = Defaults.slowLogLimitPerInterval,
        slowLogIntervalNanos: UInt64 = Defaults.slowLogIntervalNanos,
        clock: (() -> UInt64)? = nil,
        logHandler: ((String) -> Void)? = nil
    ) {
        lock.lock()
        self.enabled = enabled
        self.slowThresholdNanos = slowThresholdNanos
        self.eventLagThresholdNanos = eventLagThresholdNanos
        self.summaryIntervalNanos = summaryIntervalNanos
        self.slowLogLimitPerInterval = slowLogLimitPerInterval
        self.slowLogIntervalNanos = slowLogIntervalNanos
        self.clock = clock ?? { DispatchTime.now().uptimeNanoseconds }
        self.processStartNanos = 0
        self.logHandler = logHandler ?? { line in NSLog("%@", line) }
        self.lastSummaryNanos = 0
        self.stats.removeAll()
        self.intervalStats.removeAll()
        self.slowLogRateStates.removeAll()
        self.slowLogDropped = 0
        lock.unlock()
    }

    func resetForTesting() {
        let defaultClock = { DispatchTime.now().uptimeNanoseconds }
        lock.lock()
        enabled = Self.resolveEnabled(
            environment: ProcessInfo.processInfo.environment,
            userDefaults: .standard
        )
        slowThresholdNanos = Defaults.slowThresholdNanos
        eventLagThresholdNanos = Defaults.eventLagThresholdNanos
        summaryIntervalNanos = Defaults.summaryIntervalNanos
        slowLogLimitPerInterval = Defaults.slowLogLimitPerInterval
        slowLogIntervalNanos = Defaults.slowLogIntervalNanos
        clock = defaultClock
        processStartNanos = defaultClock()
        lastSummaryNanos = processStartNanos
        logHandler = { line in NSLog("%@", line) }
        stats.removeAll()
        intervalStats.removeAll()
        slowLogRateStates.removeAll()
        slowLogDropped = 0
        lock.unlock()
    }

    private func finish(_ probe: Probe) {
        let endNanos = clock()
        let durationNanos = endNanos >= probe.startNanos ? endNanos - probe.startNanos : 0
        let eventLagNanos = probe.metadata?.lagNanos
        let shouldLogSlow = durationNanos >= slowThresholdNanos ||
            (eventLagNanos.map { $0 >= eventLagThresholdNanos } ?? false)

        var summaryLine: String?
        var slowLine: String?
        let handler: (String) -> Void
        lock.lock()
        var stageStats = stats[probe.stage] ?? StageStats()
        stageStats.record(
            durationNanos: durationNanos,
            eventLagNanos: eventLagNanos,
            slowThresholdNanos: slowThresholdNanos,
            eventLagThresholdNanos: eventLagThresholdNanos
        )
        stats[probe.stage] = stageStats

        var intervalStageStats = intervalStats[probe.stage] ?? StageStats()
        intervalStageStats.record(
            durationNanos: durationNanos,
            eventLagNanos: eventLagNanos,
            slowThresholdNanos: slowThresholdNanos,
            eventLagThresholdNanos: eventLagThresholdNanos
        )
        intervalStats[probe.stage] = intervalStageStats

        if shouldLogSlow && shouldEmitSlowLogLocked(stage: probe.stage, atNanos: probe.startNanos) {
            slowLine = makeSlowLine(
                stage: probe.stage,
                durationNanos: durationNanos,
                metadata: probe.metadata,
                endNanos: endNanos
            )
        }
        if summaryIntervalNanos > 0 &&
            endNanos >= lastSummaryNanos &&
            endNanos - lastSummaryNanos >= summaryIntervalNanos {
            let windowNanos = endNanos - lastSummaryNanos
            lastSummaryNanos = endNanos
            summaryLine = makeSummaryLineLocked(summaryNanos: endNanos, windowNanos: windowNanos)
            intervalStats.removeAll()
        }
        handler = logHandler
        lock.unlock()

        if let slowLine {
            handler(slowLine)
        }
        if let summaryLine {
            handler(summaryLine)
        }
    }

    private func shouldEmitSlowLogLocked(stage: Stage, atNanos: UInt64) -> Bool {
        if slowLogIntervalNanos == 0 {
            return true
        }

        var state = slowLogRateStates[stage] ?? SlowLogRateState()
        if let intervalStartNanos = state.intervalStartNanos {
            if atNanos < intervalStartNanos || atNanos - intervalStartNanos >= slowLogIntervalNanos {
                state.intervalStartNanos = atNanos
                state.emittedCount = 0
            }
        } else {
            state.intervalStartNanos = atNanos
            state.emittedCount = 0
        }

        if slowLogLimitPerInterval == 0 {
            slowLogDropped &+= 1
            slowLogRateStates[stage] = state
            return false
        }

        if state.emittedCount < slowLogLimitPerInterval {
            state.emittedCount &+= 1
            slowLogRateStates[stage] = state
            return true
        }

        slowLogDropped &+= 1
        slowLogRateStates[stage] = state
        return false
    }

    private static func resolveEnabled(environment: [String: String], userDefaults: UserDefaults) -> Bool {
        if environment[Defaults.environmentKey] == "1" {
            return true
        }
        return userDefaults.bool(forKey: Defaults.userDefaultsKey)
    }

    private func makeMetadata(event: CGEvent?, now: UInt64, queueWaitStartNanos: UInt64?) -> EventMetadata? {
        let baseMetadata = event.map { metadata(for: $0, now: now) }
        guard let queueWaitStartNanos else {
            return baseMetadata
        }
        let queueWaitNanos = now >= queueWaitStartNanos ? now - queueWaitStartNanos : 0
        if let baseMetadata {
            return baseMetadata.replacingLatency(label: "queueWaitMs", nanos: queueWaitNanos)
        }
        return EventMetadata(
            source: "internal",
            type: "queue",
            code: nil,
            phase: nil,
            latencyLabel: "queueWaitMs",
            lagNanos: queueWaitNanos
        )
    }

    private func metadata(for event: CGEvent, now: UInt64) -> EventMetadata {
        let lag = event.timestamp > 0 && now >= event.timestamp ? now - event.timestamp : nil
        return EventMetadata(
            source: "cgEvent",
            type: event.eventTypeName,
            code: event.isKeyboardEvent || event.type == .flagsChanged ? event.keyCode : (event.isMouseEvent ? event.mouseCode : nil),
            phase: phaseName(for: event.type),
            latencyLabel: "eventLagMs",
            lagNanos: lag
        )
    }

    private func metadata(for inputEvent: InputEvent) -> EventMetadata {
        if case .cgEvent(let event) = inputEvent.source {
            return EventMetadata(
                source: "cgEvent",
                type: event.eventTypeName,
                code: event.isKeyboardEvent || event.type == .flagsChanged ? event.keyCode : (event.isMouseEvent ? event.mouseCode : nil),
                phase: phaseName(for: event.type),
                latencyLabel: nil,
                lagNanos: nil
            )
        }
        return EventMetadata(
            source: "hidPP",
            type: inputEvent.type.rawValue,
            code: inputEvent.code,
            phase: inputEvent.phase == .down ? "down" : "up",
            latencyLabel: nil,
            lagNanos: nil
        )
    }

    private func makeSlowLine(
        stage: Stage,
        durationNanos: UInt64,
        metadata: EventMetadata?,
        endNanos: UInt64
    ) -> String {
        var parts = [
            "[InputPipelineProfiler] slow",
            "sessionId=\(sessionId)",
            "uptimeSeconds=\(uptimeSecondsText(atNanos: endNanos))",
            "stage=\(stage.rawValue)",
            String(format: "durationMs=%.3f", Double(durationNanos) / 1_000_000.0)
        ]
        if let metadata {
            parts.append(metadata.description)
        }
        return parts.joined(separator: " ")
    }

    private func makeSummaryLineLocked(summaryNanos: UInt64, windowNanos: UInt64) -> String {
        let stageSummary = Stage.allCases.compactMap { stage -> String? in
            guard let totalItem = stats[stage], totalItem.count > 0 else { return nil }
            let intervalItem = intervalStats[stage] ?? StageStats()
            return String(
                format: "stage=%@ intervalCount=%llu intervalAvgMs=%.3f intervalMaxMs=%.3f intervalSlow=%llu intervalMaxLagMs=%.3f intervalLagSlow=%llu totalCount=%llu totalAvgMs=%.3f totalMaxMs=%.3f totalSlow=%llu totalMaxLagMs=%.3f totalLagSlow=%llu",
                stage.rawValue,
                intervalItem.count,
                Double(intervalItem.averageDurationNanos) / 1_000_000.0,
                Double(intervalItem.maxDurationNanos) / 1_000_000.0,
                intervalItem.slowCount,
                Double(intervalItem.maxEventLagNanos) / 1_000_000.0,
                intervalItem.eventLagSlowCount,
                totalItem.count,
                Double(totalItem.averageDurationNanos) / 1_000_000.0,
                Double(totalItem.maxDurationNanos) / 1_000_000.0,
                totalItem.slowCount,
                Double(totalItem.maxEventLagNanos) / 1_000_000.0,
                totalItem.eventLagSlowCount
            )
        }.joined(separator: " | ")

        return "[InputPipelineProfiler] summary sessionId=\(sessionId) uptimeSeconds=\(uptimeSecondsText(atNanos: summaryNanos)) windowSeconds=\(secondsText(windowNanos)) slowLogDropped=\(slowLogDropped) \(stageSummary)"
    }

    private func uptimeSecondsText(atNanos nanos: UInt64) -> String {
        let uptimeNanos = nanos >= processStartNanos ? nanos - processStartNanos : 0
        return secondsText(uptimeNanos)
    }

    private func secondsText(_ nanos: UInt64) -> String {
        String(format: "%.3f", Double(nanos) / 1_000_000_000.0)
    }

    private func phaseName(for type: CGEventType) -> String? {
        switch type {
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return "down"
        case .keyUp, .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return "up"
        case .flagsChanged:
            return "flags"
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return "dragged"
        default:
            return nil
        }
    }
}
