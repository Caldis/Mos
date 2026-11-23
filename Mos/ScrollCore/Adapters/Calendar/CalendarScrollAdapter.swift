import Cocoa

final class CalendarScrollAdapter: PhasedWindowScrollAdapter {
    static let descriptor = ScrollAdapterDescriptor(
        identifier: "calendar",
        bundleIdentifiers: ["com.apple.iCal"],
        minimumSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
    )

    private let scope = CalendarScrollScope()

    init() {
        super.init(descriptor: Self.descriptor)
    }

    override var outputProfile: PhasedTrackpadSink.Profile { .calendar }

    override func deactivate() {
        scope.invalidate()
        super.deactivate()
    }

    override func refresh() {
        if let application = application {
            scope.refresh(pid: application.processIdentifier) { [weak self] in
                self?.refreshWindowAfterScopeChange()
            }
        }
        super.refresh()
    }

    private func refreshWindowAfterScopeChange() {
        if let application = application, scope.viewChanged {
            ScrollPoster.shared.cancelAdapterSession(targetPID: application.processIdentifier)
        }
        super.refresh()
    }

    override func contentFrame(in window: CGRect) -> CGRect? {
        guard let frame = scope.frame else { return nil }
        let intersection = window.intersection(frame)
        return intersection.isNull || intersection.isEmpty ? nil : intersection
    }
}

final class CalendarScrollScope {
    enum View: String {
        case month = "month-button"
        case year = "year-button"

        static func selected(in identifiers: [String]) -> View? {
            guard identifiers.count == 1 else { return nil }
            return View(rawValue: identifiers[0])
        }
    }

    private let queue = DispatchQueue(label: "me.caldis.mos.calendar-scope", qos: .utility)
    private var generation = 0
    private var pending = false
    private var cachedFrame: CGRect?
    private var refreshedAt: TimeInterval = 0
    private var selectedView: View?
    private(set) var viewChanged = false
    var frame: CGRect? {
        ProcessInfo.processInfo.systemUptime - refreshedAt <= 2 ? cachedFrame : nil
    }

    func invalidate() {
        generation += 1
        cachedFrame = nil
        selectedView = nil
    }

    func refresh(pid: pid_t, completion: @escaping () -> Void) {
        guard !pending else { return }
        pending = true
        let expectedGeneration = generation
        queue.async { [weak self] in
            let result = Self.readFrame(pid: pid)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pending = false
                guard self.generation == expectedGeneration else { return }
                self.viewChanged = self.selectedView != result?.view
                self.selectedView = result?.view
                self.cachedFrame = result?.frame
                self.refreshedAt = ProcessInfo.processInfo.systemUptime
                #if DEBUG
                if self.viewChanged {
                    NSLog("CalendarScrollAdapter: scope=%@", result?.view.rawValue ?? "inactive")
                }
                #endif
                completion()
            }
        }
    }

    private static func readFrame(pid: pid_t) -> (view: View, frame: CGRect)? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement],
              let window = windows.first(where: { identifier($0) == "CALMainWindow" }),
              let toolbar = children(window).first(where: { attribute($0, kAXRoleAttribute) as? String == kAXToolbarRole }),
              let switcher = children(toolbar).first(where: { identifier($0) == "views-switcher" }) else { return nil }
        let selected = children(switcher).compactMap { element -> String? in
            guard (attribute(element, kAXValueAttribute) as? NSNumber)?.boolValue == true else { return nil }
            return identifier(element)
        }
        guard let view = View.selected(in: selected),
              let split = children(window).first(where: { attribute($0, kAXRoleAttribute) as? String == kAXSplitGroupRole }),
              let content = children(split).first(where: { identifier($0) == "active-view" }),
              let position = attribute(content, kAXPositionAttribute),
              let size = attribute(content, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return (view, CGRect(origin: point, size: extent))
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func identifier(_ element: AXUIElement) -> String? {
        attribute(element, "AXIdentifier") as? String
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
