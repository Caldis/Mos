import Foundation

/// Owns the authorization lease and the resources that must end with it.
final class InputPermissionGate {
    private let lock = NSLock()
    private var authorized = false
    private var checkedAt: TimeInterval = 0
    private var releases: [UUID: () -> Void] = [:]
    let leaseDuration: TimeInterval = 2

    var isAuthorized: Bool {
        lock.lock(); defer { lock.unlock() }
        return authorized
    }

    @discardableResult
    func update(authorized value: Bool, at time: TimeInterval) -> Bool {
        lock.lock()
        let changed = authorized != value
        authorized = value
        checkedAt = time
        let callbacks = value ? [] : takeReleases()
        lock.unlock()
        // WindowServer teardown must not block event callbacks reading the revoked state.
        callbacks.forEach { $0() }
        return changed
    }

    func expire(at time: TimeInterval) -> Bool {
        lock.lock()
        guard authorized, time - checkedAt >= leaseDuration else {
            lock.unlock()
            return false
        }
        authorized = false
        let callbacks = takeReleases()
        lock.unlock()
        callbacks.forEach { $0() }
        return true
    }

    private func takeReleases() -> [() -> Void] {
        let callbacks = Array(releases.values)
        releases.removeAll()
        return callbacks
    }

    func register(activate: () -> Void, release: @escaping () -> Void) -> UUID? {
        lock.lock()
        guard authorized else {
            lock.unlock()
            release()
            return nil
        }
        let id = UUID()
        releases[id] = release
        activate()
        lock.unlock()
        return id
    }

    func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        releases.removeValue(forKey: id)
    }
}
