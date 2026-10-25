import AppKit
import SwiftUI
import PermissionFlow
import Vortex

@objc(MosOnboardingExtras)
@MainActor
final class OnboardingExtras: NSObject {
    private var flow: PermissionFlowController?
    private var windows: [NSWindow] = []
    private var finishWork: DispatchWorkItem?
    private var motionObserver: NSObjectProtocol?

    @objc func authorize(_ source: NSValue) {
        if flow == nil {
            flow = PermissionFlow.makeController(configuration: .init(
                requiredAppURLs: [Bundle.main.bundleURL], promptForAccessibilityTrust: false
            ))
        }
        flow?.authorize(pane: .accessibility, sourceFrameInScreen: source.rectValue)
    }

    @objc func closeGuide() {
        flow?.closePanel()
        flow = nil
    }

    @objc func celebrate() {
        stopCelebration()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        for screen in NSScreen.screens {
            let window = CelebrationWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                           backing: .buffered, defer: false)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: EdgeFireworks())
            window.orderFrontRegardless()
            windows.append(window)
        }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self?.stopCelebration() }
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.stopCelebration() }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    @objc func stopCelebration() {
        finishWork?.cancel()
        finishWork = nil
        if let observer = motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        motionObserver = nil
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
    }

    @objc func finish() {
        closeGuide()
        stopCelebration()
    }
}

private final class CelebrationWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct EdgeFireworks: View {
    private let systems: [VortexSystem] = (0..<4).map { _ in
        let system = VortexSystem.fireworks.makeUniqueCopy()
        system.emissionLimit = 3
        system.birthRate = 3
        return system
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<4) { index in
                    VortexView(systems[index]) {
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .tag("circle").blendMode(.plusLighter)
                    }
                    .frame(width: geometry.size.width * 0.34, height: geometry.size.height * 0.45)
                    .rotationEffect(.degrees(index >= 2 ? 180 : 0))
                    .position(x: geometry.size.width * (index % 2 == 0 ? 0.12 : 0.88),
                              y: geometry.size.height * (index >= 2 ? 0.16 : 0.84))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
