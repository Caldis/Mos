import Cocoa

extension Notification.Name {
    static let mosInputPermissionChanged = Notification.Name("mosInputPermissionChanged")
}

final class InputPermissionMonitor {
    static let shared = InputPermissionMonitor()

    // Probe results have a freshness limit independent of the check interval.
    private static let maximumProbeAge: TimeInterval = 2
    private static let schedulingMargin: TimeInterval = 0.35

    let gate: InputPermissionGate
    private let probeInterval: TimeInterval
    private let sample: () -> Bool
    private let notificationCenter: NotificationCenter
    private let schedulerQueue = DispatchQueue(label: "com.caldis.Mos.permission-scheduler", qos: .userInitiated)
    private let probeQueue = DispatchQueue(label: "com.caldis.Mos.permission-probe", qos: .utility)
    private var currentRun: Run?

    private final class Run {
        let timer: DispatchSourceTimer
        var nextProbeAt: TimeInterval?
        var hasSampled = false

        init(timer: DispatchSourceTimer, now: TimeInterval) {
            self.timer = timer
            nextProbeAt = now
        }
    }

    init(probeInterval: TimeInterval = 3,
         sample: @escaping () -> Bool = InputPermissionProbe.sample,
         notificationCenter: NotificationCenter = .default) {
        self.probeInterval = probeInterval
        self.sample = sample
        self.notificationCenter = notificationCenter
        let probeTimeout = TimeInterval(InputPermissionProbe.timeoutMilliseconds) / 1000
        gate = InputPermissionGate(leaseDuration: probeInterval + probeTimeout + Self.schedulingMargin)
    }

    var isAuthorized: Bool { gate.isAuthorized }

    func start() {
        schedulerQueue.sync {
            guard currentRun == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: schedulerQueue)
            let run = Run(timer: timer, now: ProcessInfo.processInfo.systemUptime)
            currentRun = run
            timer.setEventHandler { [weak self, weak run] in
                guard let self = self, let run = run, self.currentRun === run else { return }
                self.timerFired(for: run)
            }
            timer.schedule(deadline: .now())
            timer.resume()
        }
    }

    func stop() {
        schedulerQueue.sync {
            currentRun?.timer.cancel()
            currentRun = nil
            gate.update(authorized: false, at: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func timerFired(for run: Run) {
        let now = ProcessInfo.processInfo.systemUptime
        expireAuthorization(at: now)
        if let nextProbeAt = run.nextProbeAt, now >= nextProbeAt {
            run.nextProbeAt = nil
            // A blocked system probe must not delay tap release at lease expiry.
            probeQueue.async { [weak self, weak run] in
                guard let self = self, let run = run else { return }
                let started = ProcessInfo.processInfo.systemUptime
                let granted = self.sample()
                self.schedulerQueue.async {
                    self.completeProbe(granted: granted, started: started, for: run)
                }
            }
        }
        scheduleNextDeadline(for: run)
    }

    private func completeProbe(granted: Bool, started: TimeInterval, for run: Run) {
        guard currentRun === run else { return }
        let now = ProcessInfo.processInfo.systemUptime
        expireAuthorization(at: now)
        let maximumAge = min(Self.maximumProbeAge, gate.leaseDuration)
        let authorized = granted && now - started < maximumAge
        let changed = gate.update(authorized: authorized, at: started)
        if changed || !run.hasSampled {
            NSLog("Input permission probe: %@", authorized ? "granted" : "unavailable")
            publishChange()
        }
        run.hasSampled = true
        run.nextProbeAt = started + probeInterval
        scheduleNextDeadline(for: run)
    }

    private func scheduleNextDeadline(for run: Run) {
        let probeAt = run.nextProbeAt ?? .infinity
        let expiresAt = gate.expiresAt ?? .infinity
        let next = min(probeAt, expiresAt)
        if next.isFinite {
            let delay = max(0, next - ProcessInfo.processInfo.systemUptime)
            let leeway: DispatchTimeInterval = .milliseconds(expiresAt <= probeAt ? 25 : 100)
            run.timer.schedule(deadline: .now() + delay, leeway: leeway)
        } else {
            run.timer.schedule(deadline: .distantFuture)
        }
    }

    private func expireAuthorization(at now: TimeInterval) {
        if gate.expire(at: now) {
            NSLog("Input permission probe expired; event taps released")
            publishChange()
        }
    }

    private func publishChange() {
        DispatchQueue.main.async { [notificationCenter] in
            notificationCenter.post(name: .mosInputPermissionChanged, object: nil)
        }
    }
}
