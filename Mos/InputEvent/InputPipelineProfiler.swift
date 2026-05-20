//
//  InputPipelineProfiler.swift
//  Mos
//
//  Created by Codex on 2026/5/15.
//

import Cocoa
import Darwin
import Foundation

private final class InputPipelineProfilerLogSink {
    static let shared = InputPipelineProfilerLogSink()

    private enum Defaults {
        static let maxFileBytes: UInt64 = 64 * 1024 * 1024
        static let maxRetainedFiles = 8
    }

    private let queue = DispatchQueue(label: "com.caldis.Mos.inputPipelineProfiler.log")
    private var fileHandle: FileHandle?
    private var fileURL: URL?
    private var fileStem: String?
    private var fileIndex = 0
    private var currentFileBytes: UInt64 = 0
    private var retainedFileURLs: [URL] = []

    func write(_ line: String) {
        queue.async {
            self.writeLocked(line)
        }
    }

    func filePath() -> String {
        queue.sync {
            self.ensureFileLocked()
            return self.fileURL?.path ?? "unavailable"
        }
    }

    private func writeLocked(_ line: String) {
        ensureFileLocked()
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if currentFileBytes > 0 && currentFileBytes + UInt64(data.count) > Defaults.maxFileBytes {
            let previousPath = fileURL?.path ?? "unavailable"
            rotateFileLocked(previousPath: previousPath)
        }
        writeDataLocked(data)
    }

    private func ensureFileLocked() {
        if fileHandle != nil { return }

        let logsDirectory = (FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true))
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Mos", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        fileStem = logsDirectory
            .appendingPathComponent("input-pipeline-profiler-\(timestamp)-\(ProcessInfo.processInfo.processIdentifier)")
            .path
        openNextFileLocked()
    }

    private func openNextFileLocked() {
        guard let fileStem else { return }
        let suffix = fileIndex == 0 ? ".log" : "-part\(fileIndex).log"
        fileIndex += 1
        let url = URL(fileURLWithPath: fileStem + suffix)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: url)
        fileURL = url
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        currentFileBytes = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        retainedFileURLs.append(url)
        trimRetainedFilesLocked()
    }

    private func rotateFileLocked(previousPath: String) {
        fileHandle?.closeFile()
        fileHandle = nil
        openNextFileLocked()
        let currentPath = fileURL?.path ?? "unavailable"
        let maxFileMB = Defaults.maxFileBytes / 1024 / 1024
        let line = "[InputPipelineProfiler] logRotated previous=\(metadataValue(previousPath)) current=\(metadataValue(currentPath)) maxFileMB=\(maxFileMB) retainedFiles=\(Defaults.maxRetainedFiles)"
        guard let data = (line + "\n").data(using: .utf8) else { return }
        writeDataLocked(data)
    }

    private func writeDataLocked(_ data: Data) {
        guard let fileHandle = fileHandle else { return }
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        currentFileBytes &+= UInt64(data.count)
    }

    private func trimRetainedFilesLocked() {
        while retainedFileURLs.count > Defaults.maxRetainedFiles {
            let url = retainedFileURLs.removeFirst()
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func metadataValue(_ value: String) -> String {
        String(value.map { character in
            character.isWhitespace || character == "|" ? "_" : character
        })
    }
}

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
        case hidInputReportCallback
        case hidReportSend
        case logiDebugLog
        case mainRunLoopHeartbeat
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

    struct SystemTopProcess: Equatable {
        let pid: Int
        let cpuPercent: Double
        let memoryPercent: Double
        let command: String
    }

    struct SystemHealthSnapshot: Equatable {
        let load1: Double
        let load5: Double
        let load15: Double
        let activeProcessorCount: Int
        let physicalMemoryMB: UInt64
        let residentMemoryMB: UInt64?
        let topProcesses: [SystemTopProcess]

        static let empty = SystemHealthSnapshot(
            load1: 0,
            load5: 0,
            load15: 0,
            activeProcessorCount: 0,
            physicalMemoryMB: 0,
            residentMemoryMB: nil,
            topProcesses: []
        )
    }

    struct Probe {
        fileprivate let profiler: InputPipelineProfiler
        fileprivate let stage: Stage
        fileprivate let startNanos: UInt64
        fileprivate let metadata: ProbeMetadata?

        func end() {
            profiler.finish(self)
        }
    }

    fileprivate enum ProbeMetadata {
        case event(EventMetadata)
        case text(String)
        case lazyText(() -> String?)

        var lagNanos: UInt64? {
            switch self {
            case .event(let metadata):
                return metadata.lagNanos
            case .text, .lazyText:
                return nil
            }
        }

        var description: String? {
            switch self {
            case .event(let metadata):
                return metadata.description
            case .text(let text):
                return text
            case .lazyText(let provider):
                return provider()
            }
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
        static let infoPlistEnabledKey = "InputPipelineProfilingEnabledByDefault"
        static let diagnosticBuildLabelKey = "MOSDiagnosticBuildLabel"
        static let slowThresholdNanos: UInt64 = 20_000_000
        static let eventLagThresholdNanos: UInt64 = 100_000_000
        static let summaryIntervalNanos: UInt64 = 60_000_000_000
        static let slowLogLimitPerInterval: UInt64 = 30
        static let slowLogIntervalNanos: UInt64 = 60_000_000_000
        static let mainRunLoopHeartbeatIntervalNanos: UInt64 = 1_000_000_000
        static let systemHealthIntervalSeconds: TimeInterval = 60
        static let systemHealthTopProcessLimit = 10
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
    private var heartbeatTimer: Timer?
    private var heartbeatExpectedNanos: UInt64?
    private let systemHealthQueue = DispatchQueue(label: "com.caldis.Mos.inputPipelineProfiler.systemHealth", qos: .utility)
    private var systemHealthTimer: DispatchSourceTimer?

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
        logHandler = Self.defaultLogHandler
    }

    @inline(__always)
    func begin(_ stage: Stage, event: CGEvent? = nil, queueWaitStartNanos: UInt64? = nil) -> Probe? {
        guard enabled else { return nil }
        let now = clock()
        return Probe(
            profiler: self,
            stage: stage,
            startNanos: now,
            metadata: makeMetadata(event: event, now: now, queueWaitStartNanos: queueWaitStartNanos).map { .event($0) }
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
            metadata: .event(metadata(for: inputEvent))
        )
    }

    @inline(__always)
    func begin(_ stage: Stage, metadata: @escaping () -> String?) -> Probe? {
        guard enabled else { return nil }
        let now = clock()
        return Probe(
            profiler: self,
            stage: stage,
            startNanos: now,
            metadata: .lazyText(metadata)
        )
    }

    @inline(__always)
    func measure<T>(_ stage: Stage, metadata: @escaping (T) -> String?, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let startNanos = clock()
        let result = body()
        let endNanos = clock()
        let textMetadata = ProbeMetadata.lazyText { metadata(result) }
        finish(stage: stage, startNanos: startNanos, endNanos: endNanos, metadata: textMetadata)
        return result
    }

    func recordObservedDuration(_ stage: Stage, durationNanos: UInt64, metadata: String? = nil) {
        guard enabled else { return }
        let endNanos = clock()
        let startNanos = endNanos >= durationNanos ? endNanos - durationNanos : 0
        finish(stage: stage, startNanos: startNanos, endNanos: endNanos, metadata: metadata.map { .text($0) })
    }

    func startMainRunLoopHeartbeat() {
        guard enabled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let alreadyStarted = self.heartbeatTimer != nil
            let now = self.clock()
            if !alreadyStarted {
                self.heartbeatExpectedNanos = now + Defaults.mainRunLoopHeartbeatIntervalNanos
            }
            self.lock.unlock()
            guard !alreadyStarted else { return }

            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.recordMainRunLoopHeartbeatTick()
            }
            RunLoop.main.add(timer, forMode: .common)

            self.lock.lock()
            self.heartbeatTimer = timer
            self.lock.unlock()
        }
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
                format: "[InputPipelineProfiler] enabled sessionId=%@ uptimeSeconds=%@ buildLabel=%@ logFile=%@ slowThresholdMs=%.3f eventLagThresholdMs=%.3f summaryIntervalSeconds=%.1f slowLogLimit=%llu slowLogIntervalSeconds=%.1f systemHealthIntervalSeconds=%.1f",
                sessionId,
                uptimeSecondsText(atNanos: now),
                Self.diagnosticBuildLabel(),
                InputPipelineProfilerLogSink.shared.filePath(),
                Double(slowThresholdNanos) / 1_000_000.0,
                Double(eventLagThresholdNanos) / 1_000_000.0,
                Double(summaryIntervalNanos) / 1_000_000_000.0,
                slowLogLimitPerInterval,
                Double(slowLogIntervalNanos) / 1_000_000_000.0,
                Defaults.systemHealthIntervalSeconds
            )
        )
    }

    func startSystemHealthSnapshots() {
        guard enabled else { return }

        lock.lock()
        let alreadyStarted = systemHealthTimer != nil
        lock.unlock()
        guard !alreadyStarted else { return }

        systemHealthQueue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let alreadyStarted = self.systemHealthTimer != nil
            self.lock.unlock()
            guard !alreadyStarted else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.systemHealthQueue)
            timer.schedule(
                deadline: .now() + .seconds(10),
                repeating: .seconds(Int(Defaults.systemHealthIntervalSeconds)),
                leeway: .seconds(5)
            )
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                self.recordSystemHealthSnapshot(Self.makeSystemHealthSnapshot())
            }

            self.lock.lock()
            self.systemHealthTimer = timer
            self.lock.unlock()
            timer.resume()
        }
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

    func recordSystemHealthSnapshotForTesting(_ snapshot: SystemHealthSnapshot) {
        recordSystemHealthSnapshot(snapshot)
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
        self.logHandler = logHandler ?? Self.defaultLogHandler
        self.lastSummaryNanos = 0
        self.heartbeatTimer?.invalidate()
        self.heartbeatTimer = nil
        self.heartbeatExpectedNanos = nil
        self.systemHealthTimer?.cancel()
        self.systemHealthTimer = nil
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
        logHandler = Self.defaultLogHandler
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        heartbeatExpectedNanos = nil
        systemHealthTimer?.cancel()
        systemHealthTimer = nil
        stats.removeAll()
        intervalStats.removeAll()
        slowLogRateStates.removeAll()
        slowLogDropped = 0
        lock.unlock()
    }

    private func finish(_ probe: Probe) {
        let endNanos = clock()
        finish(
            stage: probe.stage,
            startNanos: probe.startNanos,
            endNanos: endNanos,
            metadata: probe.metadata
        )
    }

    private func finish(stage: Stage, startNanos: UInt64, endNanos: UInt64, metadata: ProbeMetadata?) {
        let durationNanos = endNanos >= startNanos ? endNanos - startNanos : 0
        let eventLagNanos = metadata?.lagNanos
        let shouldLogSlow = durationNanos >= slowThresholdNanos ||
            (eventLagNanos.map { $0 >= eventLagThresholdNanos } ?? false)

        var summaryLine: String?
        var slowLine: String?
        let handler: (String) -> Void
        lock.lock()
        var stageStats = stats[stage] ?? StageStats()
        stageStats.record(
            durationNanos: durationNanos,
            eventLagNanos: eventLagNanos,
            slowThresholdNanos: slowThresholdNanos,
            eventLagThresholdNanos: eventLagThresholdNanos
        )
        stats[stage] = stageStats

        var intervalStageStats = intervalStats[stage] ?? StageStats()
        intervalStageStats.record(
            durationNanos: durationNanos,
            eventLagNanos: eventLagNanos,
            slowThresholdNanos: slowThresholdNanos,
            eventLagThresholdNanos: eventLagThresholdNanos
        )
        intervalStats[stage] = intervalStageStats

        if shouldLogSlow && shouldEmitSlowLogLocked(stage: stage, atNanos: startNanos) {
            slowLine = makeSlowLine(
                stage: stage,
                durationNanos: durationNanos,
                metadata: metadata,
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

    private func recordMainRunLoopHeartbeatTick() {
        let now = clock()
        var driftNanos: UInt64 = 0

        lock.lock()
        if let expectedNanos = heartbeatExpectedNanos, now > expectedNanos {
            driftNanos = now - expectedNanos
        }
        heartbeatExpectedNanos = now + Defaults.mainRunLoopHeartbeatIntervalNanos
        lock.unlock()

        recordObservedDuration(
            .mainRunLoopHeartbeat,
            durationNanos: driftNanos,
            metadata: String(
                format: "source=mainRunLoop type=heartbeat intervalMs=%.3f",
                Double(Defaults.mainRunLoopHeartbeatIntervalNanos) / 1_000_000.0
            )
        )
    }

    private func recordSystemHealthSnapshot(_ snapshot: SystemHealthSnapshot) {
        guard enabled else { return }
        let now = clock()

        let handler: (String) -> Void
        let uptimeNanos: UInt64
        lock.lock()
        handler = logHandler
        uptimeNanos = now >= processStartNanos ? now - processStartNanos : 0
        lock.unlock()

        let residentMemoryText = snapshot.residentMemoryMB.map(String.init) ?? "unknown"
        let topProcessesText = snapshot.topProcesses.map { process in
            String(
                format: "%d:%@:%.1f:%.1f",
                process.pid,
                Self.metadataValue(process.command),
                process.cpuPercent,
                process.memoryPercent
            )
        }.joined(separator: ";")
        handler(
            String(
                format: "[InputPipelineProfiler] systemHealth sessionId=%@ uptimeSeconds=%@ load1=%.2f load5=%.2f load15=%.2f activeCPUs=%d physicalMemoryMB=%llu residentMemoryMB=%@ topProcesses=%@",
                sessionId,
                secondsText(uptimeNanos),
                snapshot.load1,
                snapshot.load5,
                snapshot.load15,
                snapshot.activeProcessorCount,
                snapshot.physicalMemoryMB,
                residentMemoryText,
                topProcessesText.isEmpty ? "none" : topProcessesText
            )
        )
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
        if userDefaults.bool(forKey: Defaults.userDefaultsKey) {
            return true
        }
        if let enabled = Bundle.main.object(forInfoDictionaryKey: Defaults.infoPlistEnabledKey) as? Bool {
            return enabled
        }
        if let enabled = Bundle.main.object(forInfoDictionaryKey: Defaults.infoPlistEnabledKey) as? String {
            return ["1", "true", "yes"].contains(enabled.lowercased())
        }
        return false
    }

    private static func makeSystemHealthSnapshot() -> SystemHealthSnapshot {
        var loads = [Double](repeating: 0, count: 3)
        let loadCount = loads.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, Int32(buffer.count))
        }
        if loadCount != 3 {
            loads = [0, 0, 0]
        }
        return SystemHealthSnapshot(
            load1: loads[0],
            load5: loads[1],
            load15: loads[2],
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            physicalMemoryMB: ProcessInfo.processInfo.physicalMemory / 1024 / 1024,
            residentMemoryMB: residentMemoryMB(),
            topProcesses: sampleTopProcesses(limit: Defaults.systemHealthTopProcessLimit)
        )
    }

    private static func residentMemoryMB() -> UInt64? {
        var info = task_basic_info_64()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info_64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO_64), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size) / 1024 / 1024
    }

    private static func sampleTopProcesses(limit: Int) -> [SystemTopProcess] {
        guard limit > 0 else { return [] }

        let process = Process()
        process.launchPath = "/bin/ps"
        process.arguments = ["-arcwwwxo", "pid,ppid,%cpu,%mem,comm"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .split(separator: "\n")
            .dropFirst()
            .prefix(limit)
            .compactMap { line in
                let columns = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
                guard columns.count == 5,
                      let pid = Int(columns[0]),
                      let cpuPercent = Double(columns[2]),
                      let memoryPercent = Double(columns[3]) else {
                    return nil
                }
                return SystemTopProcess(
                    pid: pid,
                    cpuPercent: cpuPercent,
                    memoryPercent: memoryPercent,
                    command: String(columns[4])
                )
            }
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
        metadata: ProbeMetadata?,
        endNanos: UInt64
    ) -> String {
        var parts = [
            "[InputPipelineProfiler] slow",
            "sessionId=\(sessionId)",
            "uptimeSeconds=\(uptimeSecondsText(atNanos: endNanos))",
            "stage=\(stage.rawValue)",
            String(format: "durationMs=%.3f", Double(durationNanos) / 1_000_000.0),
            "thread=\(Thread.isMainThread ? "main" : "background")"
        ]
        if let metadata {
            if let description = metadata.description {
                parts.append(description)
            }
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

    static func metadataValue(_ value: String) -> String {
        String(value.map { character in
            character.isWhitespace || character == "|" ? "_" : character
        })
    }

    private static func defaultLogHandler(_ line: String) {
        InputPipelineProfilerLogSink.shared.write(line)
        NSLog("%@", line)
    }

    private static func diagnosticBuildLabel() -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Defaults.diagnosticBuildLabelKey) as? String,
              !value.isEmpty else {
            return "none"
        }
        return metadataValue(value)
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
