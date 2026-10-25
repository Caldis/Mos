import XCTest
import Cocoa
@testable import Mos_Debug

final class InputPermissionGateTests: XCTestCase {
    func testRevocationReleasesEveryInputResourceBeforeReturning() {
        let gate = InputPermissionGate()
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
        let gate = InputPermissionGate()
        gate.update(authorized: true, at: 10)
        var released = false
        _ = gate.register(activate: {}, release: { released = true })
        XCTAssertFalse(gate.expire(at: 11))
        XCTAssertTrue(gate.expire(at: 12.1))
        XCTAssertTrue(released)
        XCTAssertFalse(gate.isAuthorized)
    }

    func testRecoveryRequiresNewResources() {
        let gate = InputPermissionGate()
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
        let gate = InputPermissionGate()
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
        let gate = InputPermissionGate()
        gate.update(authorized: true, at: 0)
        var releases = 0
        let id = gate.register(activate: {}, release: { releases += 1 })!
        gate.remove(id)
        gate.update(authorized: false, at: 1)
        XCTAssertEqual(releases, 0)
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
