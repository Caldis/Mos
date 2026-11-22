//
//  ScrollSourceFilter.swift
//  Mos
//  Source application matching and bounded identity cache for scroll passthrough.
//

import Cocoa

/// Used on the event tap's main run loop. No process enumeration or persistence in the callback.
final class ScrollSourceFilter {
    static let shared: ScrollSourceFilter = {
        let filter = ScrollSourceFilter()
        filter.setExcludedBundleIdentifiers(Options.shared.excludedScrollSourceBundleIdentifiers)
        Options.shared.observe([.scroll]) { [weak filter] _ in
            filter?.setExcludedBundleIdentifiers(Options.shared.excludedScrollSourceBundleIdentifiers)
        }
        filter.observeApplicationLifecycle()
        return filter
    }()

    private struct CacheEntry {
        let bundleIdentifier: String?
        let expiresAt: TimeInterval
    }

    private var excluded = Set<String>()
    private var cache: [pid_t: CacheEntry] = [:]
    private let resolve: (pid_t) -> String?
    private let now: () -> TimeInterval
    private var lifecycleObservers: [NSObjectProtocol] = []
    // Bound memory for many short-lived driver processes. Failed lookups retry sooner
    // because a launching application may not yet expose its bundle identifier.
    private let cacheLimit = 64
    private let resolvedLookupLifetime: TimeInterval = 5
    private let unresolvedLookupLifetime: TimeInterval = 1

    init(resolve: @escaping (pid_t) -> String? = {
        NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
    }, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.resolve = resolve
        self.now = now
    }

    deinit {
        for observer in lifecycleObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func setExcludedBundleIdentifiers(_ identifiers: [String]) {
        let updated = Set(identifiers)
        guard excluded != updated else { return }
        excluded = updated
        invalidateCache()
    }

    func invalidateCache() {
        cache.removeAll(keepingCapacity: true)
    }

    func shouldPassthrough(_ event: CGEvent) -> Bool {
        // Hardware wheel events commonly have PID zero. Unresolved sources retain
        // the existing smoothing path; an unknown source must never mean "exclude all".
        guard !excluded.isEmpty else { return false }
        let rawPID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard rawPID > 0, rawPID <= Int64(Int32.max) else { return false }
        let pid = pid_t(rawPID)
        let time = now()
        let identifier: String?
        if let entry = cache[pid], time < entry.expiresAt {
            identifier = entry.bundleIdentifier
        } else {
            identifier = resolve(pid)
            if cache.count >= cacheLimit {
                invalidateCache()
            }
            // Lifecycle notifications invalidate successful lookups; TTL also bounds stale PID reuse.
            let lifetime = identifier == nil ? unresolvedLookupLifetime : resolvedLookupLifetime
            cache[pid] = CacheEntry(bundleIdentifier: identifier, expiresAt: time + lifetime)
        }
        guard let bundleIdentifier = identifier else { return false }
        return excluded.contains(bundleIdentifier)
    }

    private func observeApplicationLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            lifecycleObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.invalidateCache()
            })
        }
    }
}
