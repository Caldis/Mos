// Mos/Logi/LogiCenter.swift
import Foundation
import Cocoa

/// The single public facade for everything Logi. External code must NOT
/// reference any other Logi type by name (CI lint enforces this from Step 5).
final class LogiCenter {
    static let shared = LogiCenter()

    // MARK: - Internal collaborators (Step 2: facade only delegates to manager;
    //                                  Step 3: registry added; Step 4: bridge filled in)
    private let manager: LogiSessionManager
    internal let registry: UsageRegistry
    internal private(set) var externalBridge: LogiExternalBridge

    // MARK: - Production init
    private init() {
        self.manager = LogiSessionManager.shared
        let mgr = self.manager  // capture for closure
        self.registry = UsageRegistry(sessionProvider: { [weak mgr] in
            return mgr?.activeSessions ?? []
        })
        self.externalBridge = LogiNoOpBridge.shared
    }

    // MARK: - Test-injectable init (Tier 2 harness)
    #if DEBUG
    internal init(manager: LogiSessionManager,
                  registry: UsageRegistry,
                  bridge: LogiExternalBridge = LogiNoOpBridge.shared) {
        self.manager = manager
        self.registry = registry
        self.externalBridge = bridge
    }
    #endif

    // MARK: - Bridge installation (DEBUG: precondition main thread)
    func installBridge(_ bridge: LogiExternalBridge) {
        #if DEBUG
        precondition(Thread.isMainThread, "installBridge must be called on main")
        #endif
        self.externalBridge = bridge
    }

    // MARK: - Lifecycle
    func start() {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.start()
    }
    func stop() {
        #if DEBUG
        precondition(Thread.isMainThread)
        #endif
        manager.stop()
    }

    // MARK: - CID directory (read-only)
    func isLogiCode(_ code: UInt16) -> Bool { LogiCIDDirectory.isLogitechCode(code) }
    func name(forMosCode code: UInt16) -> String? {
        let displayName = LogiCIDDirectory.name(forMosCode: code)
        return displayName.isEmpty ? nil : displayName
    }

    // MARK: - Conflict
    func conflictStatus(forMosCode code: UInt16) -> ConflictStatus {
        return manager.conflictStatus(forMosCode: code)
    }

    // MARK: - Recording
    var isRecording: Bool { manager.isRecording }
    func beginKeyRecording() { manager.temporarilyDivertAll() }
    func endKeyRecording() { manager.restoreDivertToBindings() }

    // MARK: - Feature actions
    func executeSmartShiftToggle() { manager.executeSmartShiftToggle() }
    func executeDPICycle(direction: Direction) { manager.executeDPICycle(direction: direction) }

    // MARK: - Reporting refresh
    func refreshReportingStates() { manager.refreshReportingStates() }

    // MARK: - Debug panel
    func showDebugPanel() {
        #if DEBUG
        precondition(Thread.isMainThread)
        #endif
        LogiDebugPanel.shared.show()
    }

    // MARK: - Activity
    var isBusy: Bool { manager.isBusy }
    var currentActivitySummary: [SessionActivityStatus] { manager.currentActivitySummary }

    // MARK: - Usage registry
    func setUsage(source: UsageSource, codes: Set<UInt16>) {
        registry.setUsage(source: source, codes: codes)
    }
    func usages(of code: UInt16) -> [UsageSource] {
        return registry.usages(of: code)
    }

    // MARK: - Snapshots
    func activeSessionsSnapshot() -> [LogiDeviceSessionSnapshot] {
        return manager.activeSessions.map { LogiDeviceSessionSnapshot(session: $0) }
    }

    // MARK: - Namespaced notifications
    static let sessionChanged        = LogiSessionManager.sessionChangedNotification
    static let discoveryStateChanged = LogiSessionManager.discoveryStateDidChangeNotification
    static let reportingDidComplete  = LogiSessionManager.reportingQueryDidCompleteNotification
    static let activityChanged       = LogiSessionManager.activityStateDidChangeNotification
    static let conflictChanged       = LogiSessionManager.conflictChangedNotification
    static let buttonEventRelay      = LogiSessionManager.buttonEventNotification
    static let rawButtonEvent        = NSNotification.Name("LogiRawButtonEvent")  // Step 4 fills in posters
}
