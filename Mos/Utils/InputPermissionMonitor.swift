import Cocoa

extension Notification.Name {
    static let mosInputPermissionChanged = Notification.Name("mosInputPermissionChanged")
}

final class InputPermissionMonitor {
    static let shared = InputPermissionMonitor()
    let gate = InputPermissionGate()
    private let probeQueue = DispatchQueue(label: "com.caldis.Mos.permission-probe", qos: .utility)
    private let watchdogQueue = DispatchQueue(label: "com.caldis.Mos.permission-watchdog", qos: .userInitiated)
    private var probeTimer: DispatchSourceTimer?
    private var watchdogTimer: DispatchSourceTimer?

    var isAuthorized: Bool { gate.isAuthorized }

    func start() {
        guard probeTimer == nil else { return }
        let probe = DispatchSource.makeTimerSource(queue: probeQueue)
        probe.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        var firstSample = true
        probe.setEventHandler { [weak self] in
            guard let self = self else { return }
            let started = ProcessInfo.processInfo.systemUptime
            let granted = InputPermissionProbe.sample()
            let now = ProcessInfo.processInfo.systemUptime
            // tccd IPC can stall during a permission edit. An old reply cannot renew the lease.
            let fresh = now - started < self.gate.leaseDuration
            let changed = self.gate.update(authorized: granted && fresh, at: started)
            if changed || firstSample {
                NSLog("Input permission probe: %@", granted && fresh ? "granted" : "unavailable")
                self.publishChange()
            }
            firstSample = false
        }
        probeTimer = probe
        probe.resume()
        let watchdog = DispatchSource.makeTimerSource(queue: watchdogQueue)
        watchdog.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(25))
        watchdog.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.gate.expire(at: ProcessInfo.processInfo.systemUptime) {
                NSLog("Input permission probe expired; event taps released")
                self.publishChange()
            }
        }
        watchdogTimer = watchdog
        watchdog.resume()
    }

    func stop() {
        probeTimer?.cancel()
        watchdogTimer?.cancel()
        probeTimer = nil
        watchdogTimer = nil
        gate.update(authorized: false, at: ProcessInfo.processInfo.systemUptime)
    }

    private func publishChange() {
        // Tap release already happened on the watchdog/probe queue, before UI cleanup.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mosInputPermissionChanged, object: nil)
        }
    }
}
