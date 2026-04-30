import Foundation

/// Registry of MosCode usages declared by preference panels and the bootstrap.
/// Push API: setUsage(source:codes:). Coalesces multiple updates in the same
/// main-queue task into one recompute.
final class UsageRegistry {

    private let sessionProvider: () -> [LogiDeviceSession]
    private let onRecompute: () -> Void   // test hook; production uses the closure-default below

    init(sessionProvider: @escaping () -> [LogiDeviceSession],
         onRecompute: @escaping () -> Void = {}) {
        self.sessionProvider = sessionProvider
        self.onRecompute = onRecompute
    }

    private var sources: [UsageSource: Set<UInt16>] = [:]
    private var aggregatedCache: Set<UInt16> = []
    private var aggregatedDirty: Bool = true
    private var recomputeScheduled: Bool = false

    /// Test-only accessor.
    #if DEBUG
    var sourcesForTests: [UsageSource: Set<UInt16>] { sources }
    #endif

    func setUsage(source: UsageSource, codes: Set<UInt16>) {
        #if DEBUG
        precondition(Thread.isMainThread, "UsageRegistry is main-thread-only")
        #endif
        let existing = sources[source]
        if existing == codes { return }
        if existing == nil && codes.isEmpty { return }
        if codes.isEmpty {
            sources.removeValue(forKey: source)
        } else {
            sources[source] = codes
        }
        aggregatedDirty = true
        scheduleRecompute()
    }

    func usages(of code: UInt16) -> [UsageSource] {
        return sources.compactMap { $0.value.contains(code) ? $0.key : nil }
    }

    var aggregatedCacheIsEmpty: Bool {
        if aggregatedDirty { return sources.values.allSatisfy { $0.isEmpty } }
        return aggregatedCache.isEmpty
    }

    private func scheduleRecompute() {
        if recomputeScheduled { return }
        recomputeScheduled = true
        DispatchQueue.main.async { [weak self] in self?.runRecompute() }
    }

    private func runRecompute() {
        recomputeScheduled = false
        if aggregatedDirty {
            aggregatedCache = sources.values.reduce(into: Set<UInt16>()) { $0.formUnion($1) }
            aggregatedDirty = false
        }
        for session in sessionProvider() where session.isHIDPPCandidate {
            session.applyUsage(aggregatedCache)
        }
        onRecompute()
    }

    /// Manual prime for newly-ready sessions (Step 3 wires this in).
    func primeSession(_ session: LogiDeviceSession) {
        if aggregatedDirty {
            aggregatedCache = sources.values.reduce(into: Set<UInt16>()) { $0.formUnion($1) }
            aggregatedDirty = false
        }
        session.applyUsage(aggregatedCache)
    }
}
