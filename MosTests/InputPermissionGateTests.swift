import XCTest
import Cocoa
@testable import Mos_Debug

final class InputPermissionProbeTests: XCTestCase {
    func testFreshChildExitStatusControlsAuthorization() {
        XCTAssertTrue(InputPermissionProbe.run(executable: URL(fileURLWithPath: "/usr/bin/true"),
                                               arguments: [], timeout: .seconds(1)))
        XCTAssertFalse(InputPermissionProbe.run(executable: URL(fileURLWithPath: "/usr/bin/false"),
                                                arguments: [], timeout: .seconds(1)))
        XCTAssertFalse(InputPermissionProbe.run(executable: URL(fileURLWithPath: "/usr/bin/MosMissingProbe"),
                                                arguments: [], timeout: .seconds(1)))
    }

    func testTimedOutChildIsReapedBeforeTheNextProbe() throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let started = ProcessInfo.processInfo.systemUptime
        let script = "printf '%s' \"$$\" > \"$1\"; exec /bin/sleep 30"
        XCTAssertFalse(InputPermissionProbe.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                                arguments: ["-c", script, "probe-test", pidFile.path],
                                                timeout: .milliseconds(250)))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 3)
        let pid = try XCTUnwrap(pid_t(String(contentsOf: pidFile, encoding: .utf8)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        XCTAssertTrue(InputPermissionProbe.run(executable: URL(fileURLWithPath: "/usr/bin/true"),
                                               arguments: [], timeout: .seconds(1)))
    }
}

final class InputPermissionGateTests: XCTestCase {
    func testRevocationReleasesEveryInputResourceBeforeReturning() {
        let gate = InputPermissionGate(leaseDuration: 2)
        gate.update(authorized: true, at: 0)
        var active = 0
        for _ in 0..<4 {
            XCTAssertNotNil(gate.register(activate: { active += 1 }, release: { active -= 1 }))
        }
        XCTAssertTrue(gate.update(authorized: false, at: 1))
        XCTAssertEqual(active, 0)
        XCTAssertFalse(gate.update(authorized: false, at: 2))
        XCTAssertEqual(active, 0)
    }

    func testBlockedPermissionProbeExpiresLease() {
        let gate = InputPermissionGate(leaseDuration: 2)
        gate.update(authorized: true, at: 10)
        XCTAssertEqual(gate.expiresAt, 12)
        var released = false
        _ = gate.register(activate: {}, release: { released = true })
        XCTAssertFalse(gate.expire(at: 11))
        XCTAssertTrue(gate.expire(at: 12))
        XCTAssertTrue(released)
        XCTAssertFalse(gate.isAuthorized)
        XCTAssertNil(gate.expiresAt)
    }

    func testRecoveryRequiresNewResources() {
        let gate = InputPermissionGate(leaseDuration: 2)
        var activations = 0
        XCTAssertNil(gate.register(activate: { activations += 1 }, release: {}))
        gate.update(authorized: true, at: 0)
        _ = gate.register(activate: { activations += 1 }, release: {})
        gate.update(authorized: false, at: 1)
        gate.update(authorized: true, at: 2)
        XCTAssertEqual(activations, 1)
        XCTAssertNotNil(gate.register(activate: { activations += 1 }, release: {}))
        XCTAssertEqual(activations, 2)
    }

    func testRevocationAllowsPassthroughWhileResourceTeardownIsStillRunning() {
        let gate = InputPermissionGate(leaseDuration: 2)
        gate.update(authorized: true, at: 0)
        let releaseStarted = DispatchSemaphore(value: 0)
        let finishRelease = DispatchSemaphore(value: 0)
        _ = gate.register(activate: {}, release: {
            releaseStarted.signal()
            _ = finishRelease.wait(timeout: .now() + 2)
        })
        DispatchQueue.global().async { gate.update(authorized: false, at: 1) }
        XCTAssertEqual(releaseStarted.wait(timeout: .now() + 1), .success)
        let checked = expectation(description: "Input callback can read revoked authorization")
        DispatchQueue.global().async {
            XCTAssertFalse(gate.isAuthorized)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 0.3)
        finishRelease.signal()
    }

    func testRemovedResourceIsNotReleasedAgain() {
        let gate = InputPermissionGate(leaseDuration: 2)
        gate.update(authorized: true, at: 0)
        var releases = 0
        let id = gate.register(activate: {}, release: { releases += 1 })!
        gate.remove(id)
        gate.update(authorized: false, at: 1)
        XCTAssertEqual(releases, 0)
    }
}

final class InputPermissionMonitorTests: XCTestCase {
    func testAuthorizedMonitorStartsProbesThreeSecondsApart() {
        let notifications = NotificationCenter()
        let authorized = expectation(description: "First probe authorizes input")
        let probesStarted = expectation(description: "Two probes start")
        probesStarted.expectedFulfillmentCount = 2
        let lock = NSLock()
        var startTimes: [TimeInterval] = []
        let monitor = InputPermissionMonitor(sample: {
            lock.lock()
            startTimes.append(ProcessInfo.processInfo.systemUptime)
            lock.unlock()
            probesStarted.fulfill()
            return true
        }, notificationCenter: notifications)
        let observer = notifications.addObserver(forName: .mosInputPermissionChanged, object: nil, queue: nil) { _ in
            XCTAssertTrue(monitor.isAuthorized)
            authorized.fulfill()
        }
        defer { notifications.removeObserver(observer) }

        monitor.start()
        wait(for: [authorized, probesStarted], timeout: 6)
        XCTAssertTrue(monitor.isAuthorized)
        monitor.stop()

        lock.lock()
        let times = startTimes
        lock.unlock()
        XCTAssertEqual(times.count, 2)
        if times.count == 2 {
            XCTAssertGreaterThanOrEqual(times[1] - times[0], 2.99)
        }
        XCTAssertEqual(monitor.gate.leaseDuration, 4.25, accuracy: 0.001)
    }

    func testBlockedProbeReleasesTapAtLeaseExpiry() {
        let notifications = NotificationCenter()
        let authorized = expectation(description: "First probe authorizes input")
        let blocked = expectation(description: "Second probe blocks")
        let released = expectation(description: "Lease releases tap before the probe returns")
        let unblock = DispatchSemaphore(value: 0)
        var firstProbe = true
        let monitor = InputPermissionMonitor(probeInterval: 0.25, sample: {
            if firstProbe {
                firstProbe = false
                return true
            }
            blocked.fulfill()
            _ = unblock.wait(timeout: .now() + 5)
            return false
        }, notificationCenter: notifications)
        let observer = notifications.addObserver(forName: .mosInputPermissionChanged, object: nil, queue: nil) { _ in
            if monitor.isAuthorized { authorized.fulfill() }
        }
        defer {
            monitor.stop()
            unblock.signal()
            notifications.removeObserver(observer)
        }

        monitor.start()
        wait(for: [authorized], timeout: 2)
        XCTAssertNotNil(monitor.gate.register(activate: {}, release: { released.fulfill() }))
        wait(for: [blocked, released], timeout: 3, enforceOrder: true)
        XCTAssertFalse(monitor.isAuthorized)
    }

    func testStoppedMonitorDiscardsAnInFlightGrant() {
        let notifications = NotificationCenter()
        let started = expectation(description: "Probe starts")
        let returning = expectation(description: "Probe returns a grant")
        let published = expectation(description: "Stopped monitor publishes a change")
        published.isInverted = true
        let unblock = DispatchSemaphore(value: 0)
        let monitor = InputPermissionMonitor(sample: {
            started.fulfill()
            _ = unblock.wait(timeout: .now() + 5)
            returning.fulfill()
            return true
        }, notificationCenter: notifications)
        let observer = notifications.addObserver(forName: .mosInputPermissionChanged, object: nil, queue: nil) { _ in
            published.fulfill()
        }
        defer {
            monitor.stop()
            unblock.signal()
            notifications.removeObserver(observer)
        }

        monitor.start()
        wait(for: [started], timeout: 2)
        monitor.stop()
        unblock.signal()
        wait(for: [returning], timeout: 2)
        wait(for: [published], timeout: 0.25)
        XCTAssertFalse(monitor.isAuthorized)
    }
}

final class InputPermissionFeedbackTests: XCTestCase {
    func testFirstDeniedSampleShowsWelcomeOnce() {
        var feedback = InputPermissionFeedback()
        XCTAssertEqual(feedback.update(authorized: false), .welcome)
        XCTAssertNil(feedback.update(authorized: false))
        XCTAssertNil(feedback.update(authorized: true))
        XCTAssertEqual(feedback.update(authorized: false), .pausedToast)
    }

    func testRevocationShowsToastOnceUntilPermissionRecovers() {
        var feedback = InputPermissionFeedback()
        XCTAssertNil(feedback.update(authorized: true))
        XCTAssertEqual(feedback.update(authorized: false), .pausedToast)
        XCTAssertNil(feedback.update(authorized: false))
        XCTAssertNil(feedback.update(authorized: true))
        XCTAssertEqual(feedback.update(authorized: false), .pausedToast)
    }
}

final class WelcomeAuthorizationStateTests: XCTestCase {
    func testCelebrationOnlyOnFirstGrantDuringFlow() {
        var state = WelcomeAuthorizationState(authorized: false)
        XCTAssertFalse(state.update(authorized: false))
        XCTAssertTrue(state.update(authorized: true))
        XCTAssertFalse(state.update(authorized: true))
        XCTAssertFalse(state.update(authorized: false))
        XCTAssertFalse(state.authorized)
        XCTAssertFalse(state.update(authorized: true))
        XCTAssertTrue(state.authorized)
    }

    func testOpeningAlreadyAuthorizedDoesNotCelebrate() {
        var state = WelcomeAuthorizationState(authorized: true)
        XCTAssertFalse(state.update(authorized: true))
    }

    func testWelcomeLayoutHasNoAmbiguityAcrossStatesAndAppearances() {
        let controller = WelcomeViewController(initialAuthorized: false)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeWindowController.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            controller.finish()
            window.close()
        }

        var appearances: [NSAppearance.Name] = [.aqua]
        if #available(macOS 10.14, *) {
            appearances.append(.darkAqua)
        }

        let renderDir = ProcessInfo.processInfo.environment["MOS_UI_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let renderDir {
            try? FileManager.default.createDirectory(at: renderDir, withIntermediateDirectories: true)
        }

        for authorized in [false, true, false] {
            controller.updateAuthorization(authorized)
            for name in appearances {
                window.appearance = NSAppearance(named: name)
                controller.view.layoutSubtreeIfNeeded()
                assertNoLayoutIssues(in: controller.view)
                if let renderDir, authorized || name == appearances.first || name == appearances.last {
                    let isDark = name != .aqua
                    let stateTag = authorized ? "auth" : "unauth"
                    let modeTag = isDark ? "dark" : "light"
                    writeWelcomeSnapshot(controller.view, dark: isDark, to: renderDir.appendingPathComponent("welcome-\(stateTag)-\(modeTag).png"))
                }
            }
        }
    }

    private func writeWelcomeSnapshot(_ view: NSView, dark: Bool, to url: URL) {
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let bg = dark ? NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1) : NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1)
        guard let backed = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: backed) else { return }
        let pxRect = NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        bg.setFill()
        pxRect.fill()
        rep.draw(in: pxRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        if let png = backed.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    func testWelcomeVectorArtworkLifecycleIsSafe() {
        let artwork = WelcomeArtworkView(reduceMotion: false)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeArtworkView.stageSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = artwork
        artwork.layoutSubtreeIfNeeded()
        artwork.updatePlayback()
        artwork.playHeroEntrance(fromCenterOffsetY: -200, heroScale: 2.05, flightDelay: 1.46)
        artwork.triggerSuccessPulse()
        artwork.setReducedMotion(true)
        artwork.stop()
        window.close()

        // Verify anchor-aware scaling introduces zero drift on standalone CALayers (anchorPoint = 0.5, 0.5).
        let standalone = CALayer()
        standalone.bounds = CGRect(x: 0, y: 0, width: 96, height: 96)
        let tStandalone = WelcomeMotion.centeredTransform(scale: 0.5, dy: 0, for: standalone)
        XCTAssertEqual(tStandalone.m41, 0, accuracy: 0.001)
        XCTAssertEqual(tStandalone.m42, 0, accuracy: 0.001)

        // Verify AppKit view-backed layers (anchorPoint = 0, 0) pivot around bounds center.
        let viewBacked = CALayer()
        viewBacked.bounds = CGRect(x: 0, y: 0, width: 96, height: 96)
        viewBacked.anchorPoint = .zero
        let tViewBacked = WelcomeMotion.centeredTransform(scale: 0.5, dy: 0, for: viewBacked)
        XCTAssertEqual(tViewBacked.m41, 24, accuracy: 0.001)
        XCTAssertEqual(tViewBacked.m42, 24, accuracy: 0.001)
    }

    private func assertNoLayoutIssues(in view: NSView, path: String = "root",
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(view.hasAmbiguousLayout, "Ambiguous layout at \(path)", file: file, line: line)
        if let field = view as? NSTextField, !field.isHidden, !field.stringValue.isEmpty {
            XCTAssertFalse(field.isEditable, "Welcome text must not be editable at \(path)", file: file, line: line)
            XCTAssertFalse(field.isSelectable, "Welcome text must not be selectable at \(path)", file: file, line: line)
            XCTAssertGreaterThan(field.frame.width, 8, "Collapsed width at \(path): \(field.stringValue)", file: file, line: line)
            XCTAssertGreaterThan(field.frame.height, 8, "Collapsed height at \(path): \(field.stringValue)", file: file, line: line)
        }
        for (index, subview) in view.subviews.enumerated() {
            assertNoLayoutIssues(in: subview, path: "\(path)/\(index):\(type(of: subview))", file: file, line: line)
        }
    }
}

final class KeyRecorderPermissionTests: XCTestCase {
    private var host: NSWindow!
    override func setUp() {
        super.setUp()
        host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
                        styleMask: [.titled], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
    }
    override func tearDown() {
        host.close()
        host = nil
        super.tearDown()
    }

    private final class Capture: RecordingEventCapture {
        var stops = 0
        func stop() { stops += 1 }
    }

    func testRevocationCancelsCaptureAndQueuedHardwareStart() {
        let capture = Capture()
        var starts = 0
        var ends = 0
        let recorder = KeyRecorder(environment: KeyRecorderEnvironment(
            isAuthorized: { true }, createCapture: { _, _ in capture },
            beginHardwareRecording: { starts += 1 }, endHardwareRecording: { ends += 1 }
        ))
        recorder.startRecording(from: host.contentView!)
        XCTAssertTrue(recorder.isRecording)
        NotificationCenter.default.post(name: .mosInputPermissionChanged, object: nil)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(capture.stops, 1)
        XCTAssertEqual(ends, 1)
        recorder.stopRecording()
        XCTAssertEqual(ends, 1)
        let drained = expectation(description: "Queued hardware start drained")
        DispatchQueue.main.async {
            XCTAssertEqual(starts, 0)
            drained.fulfill()
        }
        wait(for: [drained], timeout: 1)
    }

    func testCaptureCreationFailureCleansRecordingState() {
        var ends = 0
        let recorder = KeyRecorder(environment: KeyRecorderEnvironment(
            isAuthorized: { true }, createCapture: { _, _ in throw Interceptor.InterceptorError.eventTapCreationFailed },
            beginHardwareRecording: {}, endHardwareRecording: { ends += 1 }
        ))
        recorder.startRecording(from: host.contentView!)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(ends, 1)
    }

    func testDeniedPermissionDoesNotCreateCapture() {
        var creations = 0
        let recorder = KeyRecorder(environment: KeyRecorderEnvironment(
            isAuthorized: { false }, createCapture: { _, _ in creations += 1; return Capture() },
            beginHardwareRecording: {}, endHardwareRecording: {}
        ))
        recorder.startRecording(from: host.contentView!)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(creations, 0)
    }
}

final class OnboardingExtrasTests: XCTestCase {
    func testOptionalBundleLoadsAndCelebrationReleasesWindows() throws {
        guard #available(macOS 13, *) else { throw XCTSkip("Optional onboarding bundle requires macOS 13") }
        let url = try XCTUnwrap(Bundle.main.builtInPlugInsURL?.appendingPathComponent("MosOnboardingExtras.bundle"))
        let bundle = try XCTUnwrap(Bundle(url: url))
        XCTAssertTrue(bundle.load())
        let type = try XCTUnwrap(NSClassFromString("MosOnboardingExtras") as? NSObject.Type)
        let extras = type.init()
        XCTAssertTrue(extras.responds(to: NSSelectorFromString("authorize:")))
        let keyWindow = NSApp.keyWindow
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        _ = extras.perform(NSSelectorFromString("celebrate"))
        let created = NSApp.windows.filter { !existing.contains(ObjectIdentifier($0)) && $0.isVisible }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertTrue(created.isEmpty)
        } else {
            XCTAssertEqual(created.count, NSScreen.screens.count)
            for window in created {
                XCTAssertTrue(window.ignoresMouseEvents)
                XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllApplications))
                XCTAssertFalse(window.canBecomeKey)
                XCTAssertFalse(window.canBecomeMain)
            }
        }
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
        _ = extras.perform(NSSelectorFromString("finish"))
        XCTAssertTrue(created.allSatisfy { !$0.isVisible && $0.contentView == nil })
    }
}
