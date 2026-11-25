import AppKit
import Darwin
import QuartzCore
import os

enum ScrollPipelineBenchmark {
    struct Display: Encodable {
        let id: CGDirectDisplayID
        let name: String
        let hz: Double
    }

    struct Sample: Encodable {
        let stream: String
        let timestamp: Double
        var y: Double = 0
        var x: Double = 0
        var interval: Double = 0
        var eventTimestamp: String?
    }

    struct Selection: Encodable {
        let planUs: Double
        let bindingUs: Double
    }

    struct Start: Encodable {
        let phase: String
        let clock: String
        let clockDisplayID: CGDirectDisplayID?
        let targetHz: Double?
        let selection: Selection
        let submitUs: Double
        let firstTickMs: Double
        let firstMovementMs: Double
    }

    struct Run: Encodable {
        let mode: String
        let display: Display
        let clock: String
        let clockDisplay: Display?
        let normalized: Bool
        let targetHz: Double?
        let inputs: Int
        let firstInput: Double
        let measurementStart: Double?
        let measurementEnd: Double?
        let cpuSeconds: Double?
        let firstSelection: Selection?
        let samples: [Sample]
        let drops: UInt64
        let naturalStop: Bool?
    }

    private static var lock = os_unfair_lock_s()
    private static var samples = [Sample]()
    private static var selections = [Selection]()
    static var targetHz: Double?
    static var pinnedDisplay: CGDirectDisplayID?
    static var testTargetHz: Double?
    static var inputDisplay: Display?
    private static let ticksPerSecond: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return 1e9 * Double(timebase.denom) / Double(timebase.numer)
    }()

    static func recordOutput(_ event: CGEvent, targetPID: pid_t) {
        precondition(targetPID == getpid())
        append(Sample(stream: "output", timestamp: CACurrentMediaTime(),
                      y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
                      x: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                      eventTimestamp: String(event.timestamp)))
    }

    static func recordTick(timestamp: Double, interval: Double) {
        append(Sample(stream: "clock", timestamp: timestamp, interval: interval))
    }

    static func recordPacedTick(timestamp: Double, interval: Double) {
        append(Sample(stream: "paced", timestamp: timestamp, interval: interval))
    }

    static func recordSmoothed(y: Double, x: Double) {
        append(Sample(stream: "smoothed", timestamp: CACurrentMediaTime(), y: y, x: x))
    }

    static func recordSelection(plan: Double, binding: Double) {
        selections.append(Selection(planUs: plan * 1e6, bindingUs: binding * 1e6))
    }

    private static func append(_ sample: Sample) {
        os_unfair_lock_lock(&lock)
        samples.append(sample)
        os_unfair_lock_unlock(&lock)
    }

    private static func outputJSON<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        FileHandle.standardOutput.write(data)
        print()
    }

    private static func cpuTime() -> Double {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private static func waitUntil(_ target: UInt64) {
        while mach_absolute_time() < target {
            _ = mach_wait_until(target)
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static func hasMovement() -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return samples.contains { $0.stream == "output" && ($0.x != 0 || $0.y != 0) }
    }

    private static func drainOutputs() {
        var drained = false
        ScrollDispatchContext.shared.afterPendingAdapterOutput { drained = true }
        let deadline = CACurrentMediaTime() + 1
        while !drained && CACurrentMediaTime() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.004))
        }
        precondition(drained)
    }

    private static func captureStarts(poster: ScrollPoster, event: CGEvent, options: OPTIONS_SCROLL_DEFAULT,
                                      alternate: CGPoint?) throws {
        var result = [Start]()
        let original = event.location
        let lastIndex = alternate == nil ? 6 : 8
        for index in 0...lastIndex {
            let phase: String
            if index == 6 {
                guard poster.invalidateBenchmarkFrameRate() else { break }
                phase = "invalidated"
            } else if index == 7, let alternate {
                event.location = alternate
                phase = "cross"
            } else if index == 8 {
                event.location = original
                phase = "return"
            } else {
                phase = index == 0 ? "cold" : "warm"
            }
            samples.removeAll(keepingCapacity: true)
            selections.removeAll(keepingCapacity: true)
            event.timestamp = DispatchTime.now().uptimeNanoseconds
            let start = CACurrentMediaTime()
            poster.update(event: event, duration: options.durationTransition, y: options.step, x: 0,
                          speed: options.speed, targetPID: getpid()).tryStart()
            let submitted = CACurrentMediaTime()
            while !hasMovement() && CACurrentMediaTime() < start + 0.75 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.004))
            }

            let clock = poster.benchmarkClockName
            let display = poster.benchmarkDisplayID
            poster.stop()
            drainOutputs()
            guard let selection = selections.first,
                  let tick = samples.first(where: { $0.stream == "paced" }) ?? samples.first(where: { $0.stream == "clock" }),
                  let motion = samples.first(where: { $0.stream == "output" && ($0.x != 0 || $0.y != 0) }) else {
                fatalError("The first-frame probe did not produce motion")
            }
            result.append(Start(phase: phase, clock: clock, clockDisplayID: display, targetHz: targetHz,
                                selection: selection, submitUs: (submitted - start) * 1e6,
                                firstTickMs: (tick.timestamp - start) * 1e3,
                                firstMovementMs: (motion.timestamp - start) * 1e3))
        }
        poster.stopKeeper()
        try outputJSON(result)
    }

    static func run(_ args: [String]) throws {
        precondition(args.first == "--mos-scroll-benchmark")
        NSApplication.shared.setActivationPolicy(.prohibited)
        let screenNumber = NSDeviceDescriptionKey("NSScreenNumber")
        let displays = NSScreen.screens.compactMap { screen -> Display? in
            guard let id = (screen.deviceDescription[screenNumber] as? NSNumber)?.uint32Value else { return nil }
            let nominal = CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0
            let hz = nominal > 0 ? nominal : Double(screen.maximumFramesPerSecond)
            return Display(id: id, name: screen.localizedName, hz: hz)
        }
        if args[1] == "displays" {
            try outputJSON(displays)
            return
        }

        let mode = args[1]
        let isCPU = mode == "cpu"
        precondition(isCPU || mode == "curves" || mode == "selection" || mode == "starts")
        let normalized = args[3] == "on"
        let id = CGDirectDisplayID(args[2])
        guard let display = displays.first(where: { $0.id == id }) else {
            fatalError("The requested display is unavailable")
        }
        inputDisplay = display
        pinnedDisplay = value(after: "--pin-display", in: args).flatMap { CGDirectDisplayID($0) }
        testTargetHz = value(after: "--test-target-hz", in: args).flatMap { Double($0) }
        let bounds = CGDisplayBounds(display.id)
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        Options.shared.configureBenchmark(normalized: normalized)
        let options = Options.shared.scroll
        let poster = ScrollPoster.shared
        poster.create()
        if mode == "selection" {
            for _ in 0..<31 { poster.measureBenchmarkSelection() }
            poster.stopKeeper()
            try outputJSON(selections)
            return
        }
        poster.startKeeper()

        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                  wheel1: 1, wheel2: 0, wheel3: 0) else {
            fatalError("Could not construct the fixture event")
        }
        event.location = point
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(getpid()))
        samples.reserveCapacity(1_024)
        ScrollDispatchContext.shared.resetDiagnostics()
        if mode == "starts" {
            let alternate = value(after: "--alternate-display", in: args).flatMap { CGDirectDisplayID($0) }.map { id in
                let bounds = CGDisplayBounds(id)
                return CGPoint(x: bounds.midX, y: bounds.midY)
            }
            try captureStarts(poster: poster, event: event, options: options, alternate: alternate)
            return
        }

        let start = mach_absolute_time()
        let warmupInputs = 40
        let measuredInputs = 240
        let count = isCPU ? warmupInputs + measuredInputs : 6
        let gap = isCPU ? 1.0 / 80 : 0.028
        var firstInput = 0.0
        var measurementStart: Double?
        var measurementEnd: Double?
        var startCPU: Double?
        var measuredCPU: Double?

        for index in 0..<count {
            waitUntil(start + UInt64(Double(index) * gap * ticksPerSecond))
            if isCPU && index == warmupInputs {
                startCPU = cpuTime()
                measurementStart = CACurrentMediaTime()
            }
            event.timestamp = DispatchTime.now().uptimeNanoseconds
            let now = CACurrentMediaTime()
            if index == 0 { firstInput = now }
            if !isCPU {
                append(Sample(stream: "input", timestamp: now, y: options.step, interval: Double(index) * gap,
                              eventTimestamp: String(event.timestamp)))
            }
            poster.update(event: event, duration: options.durationTransition, y: options.step, x: 0,
                          speed: options.speed, targetPID: getpid()).tryStart()
        }

        if isCPU {
            waitUntil(start + UInt64(Double(count) * gap * ticksPerSecond))
            measurementEnd = CACurrentMediaTime()
            measuredCPU = cpuTime() - startCPU!
        } else {
            while poster.benchmarkRunning && CACurrentMediaTime() < firstInput + 3 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }

        let actualClock = poster.benchmarkClockName
        let boundDisplay = displays.first(where: { $0.id == poster.benchmarkDisplayID })
        let stopped = !poster.benchmarkRunning
        poster.stop()
        poster.stopKeeper()
        drainOutputs()
        let health = poster.diagnosticsSnapshot()
        let drops = health.droppedFramesByGeneration + health.droppedFramesByTTL + health.updateSnapshotFailures
        try outputJSON(Run(mode: mode, display: display, clock: actualClock, clockDisplay: boundDisplay,
                           normalized: normalized, targetHz: targetHz, inputs: isCPU ? measuredInputs : count, firstInput: firstInput,
                           measurementStart: measurementStart, measurementEnd: measurementEnd, cpuSeconds: measuredCPU,
                           firstSelection: selections.first,
                           samples: samples.sorted { $0.timestamp < $1.timestamp }, drops: drops,
                           naturalStop: isCPU ? nil : stopped))
    }
}

try ScrollPipelineBenchmark.run(Array(CommandLine.arguments.dropFirst()))
