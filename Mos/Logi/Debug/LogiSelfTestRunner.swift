//
//  LogiSelfTestRunner.swift
//  Mos
//
//  DEBUG-only step runner that drives the Self-Test Wizard. Skeleton —
//  detailed Bolt/BLE step lists per spec §7 Tier 3c land in a later pass.
//

#if DEBUG
import Foundation

/// What kind of action a wizard step performs.
/// Closure-based instead of async/await to stay compatible with
/// macOS 10.13 deployment target.
enum StepKind {
    case automatic(detail: String,
                   run: (@escaping (StepOutcome) -> Void) -> Void)
    case physicalAutoVerified(instruction: String,
                              expectation: String,
                              wait: WaitCondition,
                              timeout: TimeInterval)
    case physicalUserConfirmed(instruction: String,
                               expectation: String,
                               confirmPrompt: String)
}

/// Async wait condition for a `physicalAutoVerified` step. The wizard
/// observes a notification or a session state transition and resolves.
enum WaitCondition {
    case rawButtonEvent(mosCode: UInt16?, cid: UInt16?)
    case sessionConnected(mode: LogiDeviceSession.ConnectionMode)
    case sessionDisconnected
    case divertApplied(cid: UInt16, expectBit0: Bool)
    case dpiChanged(direction: Direction)
}

enum StepOutcome {
    case pass
    case fail(reason: String)
}

/// Read-only description of a session reachable for the wizard.
enum DetectedConnection {
    case bolt(snapshot: LogiDeviceSessionSnapshot, slot: UInt8, name: String)
    case bleDirect(snapshot: LogiDeviceSessionSnapshot, name: String)
}

/// Single self-test step shown in the wizard.
struct Step {
    let index: Int          // 1-based
    let total: Int
    let title: String       // 1-line
    let instruction: String
    let expectation: String
    let kind: StepKind
}

final class LogiSelfTestRunner {

    /// Inspect the first active session and classify connection mode.
    /// Returns nil when no session is reachable or when mode is unsupported.
    func detectConnection() -> DetectedConnection? {
        guard let snapshot = LogiCenter.shared.activeSessionsSnapshot().first else { return nil }
        switch snapshot.connectionMode {
        case .receiver:
            guard let firstConnected = snapshot.pairedDevices.first(where: { $0.isConnected }) else { return nil }
            return .bolt(snapshot: snapshot, slot: firstConnected.slot, name: firstConnected.name)
        case .bleDirect:
            return .bleDirect(snapshot: snapshot, name: snapshot.deviceInfo.name)
        case .unsupported:
            return nil
        }
    }

    // TODO: buildBLESuite() / runStep(_:) / handleCancel()
    // Spec §7 Tier 3c enumerates the full step lists; current
    // buildBoltSuite() is a minimal 2-step example.
}

extension LogiSelfTestRunner {

    /// Minimal Bolt suite — 2 example steps. Future expansion adds the
    /// full §7 Tier 3c step list.
    func buildBoltSuite() -> [Step] {
        var steps: [Step] = []
        steps.append(Step(
            index: 1, total: 2,
            title: "Bolt receiver detection",
            instruction: "Confirm a Logi Bolt receiver is connected and a paired device is reachable.",
            expectation: "LogiCenter reports an active session whose connectionMode == .receiver.",
            kind: .automatic(detail: "Reads detectConnection() and asserts a .bolt result.") { completion in
                let outcome: StepOutcome
                if case .bolt = self.detectConnection() {
                    outcome = .pass
                } else {
                    outcome = .fail(reason: "detectConnection did not return .bolt")
                }
                completion(outcome)
            }
        ))
        steps.append(Step(
            index: 2, total: 2,
            title: "Back button raw event",
            instruction: "Press the Back button on your Logi mouse within 30 seconds.",
            expectation: "rawButtonEvent fires with mosCode = 1006 (Back).",
            kind: .physicalAutoVerified(
                instruction: "Press the Back button on your Logi mouse within 30 seconds.",
                expectation: "rawButtonEvent fires with mosCode 1006.",
                wait: .rawButtonEvent(mosCode: 1006, cid: nil),
                timeout: 30
            )
        ))
        return steps
    }
}
#endif
