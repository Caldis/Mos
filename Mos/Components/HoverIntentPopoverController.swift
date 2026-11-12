//
//  HoverIntentPopoverController.swift
//  Mos
//

import Cocoa

struct HoverIntentPopoverConfiguration {
    var corridorPadding: CGFloat = 12
    var intentTimeout: TimeInterval = 0.6
    var closeEvaluationInterval: TimeInterval = 0.03
}

enum HoverIntentPopoverGeometry {
    static func shouldKeepOpen(
        pointer: NSPoint,
        sourceFrame: NSRect,
        popoverFrame: NSRect,
        corridorPadding: CGFloat
    ) -> Bool {
        let source = sourceFrame.insetBy(dx: -corridorPadding, dy: -corridorPadding)
        let popover = popoverFrame.insetBy(dx: -corridorPadding, dy: -corridorPadding)

        if source.contains(pointer) || popover.contains(pointer) {
            return true
        }

        let sourceCenter = NSPoint(x: source.midX, y: source.midY)
        let popoverCenter = NSPoint(x: popover.midX, y: popover.midY)
        let deltaX = popoverCenter.x - sourceCenter.x
        let deltaY = popoverCenter.y - sourceCenter.y

        let polygon: [NSPoint]
        if abs(deltaY) >= abs(deltaX) {
            if deltaY >= 0 {
                polygon = [
                    NSPoint(x: source.minX, y: source.maxY),
                    NSPoint(x: source.maxX, y: source.maxY),
                    NSPoint(x: popover.maxX, y: popover.minY),
                    NSPoint(x: popover.minX, y: popover.minY),
                ]
            } else {
                polygon = [
                    NSPoint(x: source.minX, y: source.minY),
                    NSPoint(x: source.maxX, y: source.minY),
                    NSPoint(x: popover.maxX, y: popover.maxY),
                    NSPoint(x: popover.minX, y: popover.maxY),
                ]
            }
        } else {
            if deltaX >= 0 {
                polygon = [
                    NSPoint(x: source.maxX, y: source.maxY),
                    NSPoint(x: source.maxX, y: source.minY),
                    NSPoint(x: popover.minX, y: popover.minY),
                    NSPoint(x: popover.minX, y: popover.maxY),
                ]
            } else {
                polygon = [
                    NSPoint(x: source.minX, y: source.maxY),
                    NSPoint(x: source.minX, y: source.minY),
                    NSPoint(x: popover.maxX, y: popover.minY),
                    NSPoint(x: popover.maxX, y: popover.maxY),
                ]
            }
        }

        return contains(pointer, inConvexPolygon: polygon)
    }

    private static func contains(_ point: NSPoint, inConvexPolygon polygon: [NSPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var previousSign: Bool?
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            let cross = (next.x - current.x) * (point.y - current.y)
                - (next.y - current.y) * (point.x - current.x)

            if abs(cross) < 0.0001 {
                continue
            }

            let sign = cross > 0
            if let previousSign, previousSign != sign {
                return false
            }
            previousSign = sign
        }

        return true
    }
}

final class HoverIntentPopoverController: NSObject, NSPopoverDelegate {
    var onDidClose: (() -> Void)?

    private let configuration: HoverIntentPopoverConfiguration
    private weak var sourceView: NSView?
    private var sourceRect: NSRect = .zero
    private var popover: NSPopover?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var evaluationTimer: Timer?
    private var intentDeadline: Date?
    private let monitoredEvents: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
    ]

    init(configuration: HoverIntentPopoverConfiguration = HoverIntentPopoverConfiguration()) {
        self.configuration = configuration
        super.init()
    }

    func show(
        _ popover: NSPopover,
        relativeTo rect: NSRect,
        of sourceView: NSView,
        preferredEdge: NSRectEdge
    ) {
        close()
        self.popover = popover
        self.sourceView = sourceView
        self.sourceRect = rect
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.show(relativeTo: rect, of: sourceView, preferredEdge: preferredEdge)
    }

    func sourceMouseExited() {
        guard popover != nil else { return }
        intentDeadline = Date().addingTimeInterval(configuration.intentTimeout)
        installMouseMonitorsIfNeeded()
        startEvaluationTimer()
        evaluateCurrentPointer()
    }

    func close() {
        guard let activePopover = popover else {
            cleanup(notify: false)
            return
        }
        cleanup(notify: true)
        activePopover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closedPopover = notification.object as? NSPopover,
              closedPopover === popover else {
            return
        }
        cleanup(notify: true)
    }

    private func installMouseMonitorsIfNeeded() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: monitoredEvents) { [weak self] event in
                self?.handleMouseEvent(event)
                return event
            }
        }

        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: monitoredEvents) { [weak self] event in
                self?.handleMouseEvent(event)
            }
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            closeIfPointerIsOutsideInteractiveFrames()
        default:
            evaluateCurrentPointer()
        }
    }

    private func startEvaluationTimer() {
        evaluationTimer?.invalidate()
        let timer = Timer(timeInterval: configuration.closeEvaluationInterval, repeats: true) { [weak self] _ in
            self?.evaluateCurrentPointer()
        }
        RunLoop.main.add(timer, forMode: .common)
        evaluationTimer = timer
    }

    private func evaluateCurrentPointer() {
        guard let sourceFrame = sourceFrameInScreen(),
              let popoverFrame = popoverFrameInScreen() else {
            closeIfIntentExpired()
            return
        }

        let pointer = NSEvent.mouseLocation
        let keepOpen = HoverIntentPopoverGeometry.shouldKeepOpen(
            pointer: pointer,
            sourceFrame: sourceFrame,
            popoverFrame: popoverFrame,
            corridorPadding: configuration.corridorPadding
        )

        guard keepOpen else {
            close()
            return
        }

        if popoverFrame.insetBy(dx: -configuration.corridorPadding, dy: -configuration.corridorPadding).contains(pointer) {
            intentDeadline = nil
            return
        }

        closeIfIntentExpired()
    }

    private func closeIfIntentExpired() {
        guard let intentDeadline, Date() >= intentDeadline else { return }
        close()
    }

    private func closeIfPointerIsOutsideInteractiveFrames() {
        guard let sourceFrame = sourceFrameInScreen(),
              let popoverFrame = popoverFrameInScreen() else {
            close()
            return
        }

        let pointer = NSEvent.mouseLocation
        let source = sourceFrame.insetBy(dx: -configuration.corridorPadding, dy: -configuration.corridorPadding)
        let popover = popoverFrame.insetBy(dx: -configuration.corridorPadding, dy: -configuration.corridorPadding)
        if source.contains(pointer) || popover.contains(pointer) {
            return
        }

        close()
    }

    private func sourceFrameInScreen() -> NSRect? {
        guard let sourceView,
              let window = sourceView.window else {
            return nil
        }
        let frameInWindow = sourceView.convert(sourceRect, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func popoverFrameInScreen() -> NSRect? {
        return popover?.contentViewController?.view.window?.frame
    }

    private func cleanup(notify: Bool) {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        intentDeadline = nil
        sourceView = nil
        popover = nil

        if notify {
            onDidClose?()
        }
    }
}

#if DEBUG
extension HoverIntentPopoverController {
    var testingHasPopover: Bool {
        return popover != nil
    }

    func testingInstallPopover(_ popover: NSPopover) {
        close()
        self.popover = popover
        popover.delegate = self
    }
}
#endif
