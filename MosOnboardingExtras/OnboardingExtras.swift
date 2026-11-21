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
            window.contentView = NSHostingView(rootView: CornerConfettiCannons())
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.50, execute: work)
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

private struct ConfettiTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CornerConfettiCannons: View {
    private static let palette: [VortexSystem.Color] = [
        VortexSystem.Color(red: 1.00, green: 0.31, blue: 0.38), // coral red
        VortexSystem.Color(red: 1.00, green: 0.78, blue: 0.16), // warm gold
        VortexSystem.Color(red: 0.16, green: 0.87, blue: 0.56), // Mos mint
        VortexSystem.Color(red: 0.18, green: 0.62, blue: 1.00), // Mos sky blue
        VortexSystem.Color(red: 0.74, green: 0.36, blue: 1.00), // Mos orchid
        VortexSystem.Color(red: 1.00, green: 0.40, blue: 0.74), // festive pink
        VortexSystem.Color(red: 1.00, green: 0.56, blue: 0.18), // tangerine
        VortexSystem.Color(red: 0.16, green: 0.84, blue: 0.96)  // bright cyan
    ]

    private static let confettiTags: [String] = [
        "ribbon", "ribbon",
        "rect", "rect",
        "strip",
        "square",
        "triangle",
        "circle"
    ]

    private static func makeCannon(isLeft: Bool) -> VortexSystem {
        VortexSystem(
            tags: confettiTags,
            position: isLeft ? [0.005, 0.99] : [0.995, 0.99],
            shape: .box(width: 0.032, height: 0.032),
            birthRate: 1500,
            emissionLimit: 330,
            emissionDuration: 1.0,
            lifespan: 6.15,
            lifespanVariation: 1.35,
            speed: 2.45,
            speedVariation: 1.40,
            angle: .degrees(isLeft ? 38 : -38),
            angleRange: .degrees(38),
            acceleration: [0, 0.42],
            dampingFactor: 12.2,
            angularSpeedVariation: [12, 12, 9],
            colors: .random(palette),
            size: 1.0,
            sizeVariation: 0.65,
            sizeMultiplierAtDeath: 0.85
        )
    }

    private let cannons: [VortexSystem] = [
        CornerConfettiCannons.makeCannon(isLeft: true),
        CornerConfettiCannons.makeCannon(isLeft: false)
    ]

    @State private var overlayOpacity: Double = 1.0

    var body: some View {
        ZStack {
            ForEach(cannons) { system in
                VortexView(system, targetFrameRate: 120) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 18, height: 7)
                        .tag("ribbon")

                    Capsule()
                        .fill(.white)
                        .frame(width: 22, height: 5)
                        .tag("strip")

                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 13, height: 9)
                        .tag("rect")

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.white)
                        .frame(width: 11, height: 11)
                        .tag("square")

                    ConfettiTriangle()
                        .fill(.white)
                        .frame(width: 12, height: 11)
                        .tag("triangle")

                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .tag("circle")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .opacity(overlayOpacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: 5_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 1.10)) {
                overlayOpacity = 0
            }
        }
    }
}
