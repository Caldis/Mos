import Cocoa

class ScrollSmoothDetailSettingsPopoverViewController: AdaptivePopover, ScrollOptionsContextProviding {

    @IBOutlet weak var verticalSmoothCheckBox: NSButton?
    @IBOutlet weak var horizontalSmoothCheckBox: NSButton?
    @IBOutlet weak var simulateTrackpadCheckBox: NSButton?
    private(set) var applicationCompatibilityCheckBox: NSButton?

    var currentTargetApplication: Application?
    var onOptionsChanged: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        installApplicationCompatibilityControl()
        syncViewWithOptions()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncViewWithOptions()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    @IBAction func verticalSmoothToggle(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smoothVertical = sender.state == .on
        syncViewWithOptions()
        onOptionsChanged?()
    }

    @IBAction func horizontalSmoothToggle(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smoothHorizontal = sender.state == .on
        syncViewWithOptions()
        onOptionsChanged?()
    }

    @IBAction func simulateTrackpadToggle(_ sender: NSButton) {
        let scrollOptions = getTargetApplicationScrollOptions()
        let isOn = sender.state == .on
        let wasOn = scrollOptions.smoothSimTrackpad
        scrollOptions.smoothSimTrackpad = isOn
        if isOn {
            if !wasOn {
                scrollOptions.durationBeforeSimTrackpadLock = scrollOptions.duration
            }
            scrollOptions.duration = ScrollDurationLimits.simulateTrackpadDefault
        } else {
            if wasOn, let previous = scrollOptions.durationBeforeSimTrackpadLock {
                scrollOptions.duration = previous
            }
            if wasOn {
                scrollOptions.durationBeforeSimTrackpadLock = nil
            }
        }
        syncViewWithOptions()
        onOptionsChanged?()
    }

    private func syncViewWithOptions() {
        updateSimulateTrackpadControl(simulateTrackpadCheckBox)
        let scroll = getTargetApplicationScrollOptions()
        updateSmoothDependentControl(verticalSmoothCheckBox, isOn: scroll.smoothVertical)
        updateSmoothDependentControl(horizontalSmoothCheckBox, isOn: scroll.smoothHorizontal)
        applicationCompatibilityCheckBox?.state = scroll.usesApplicationScrollAdapters ? .on : .off
        applicationCompatibilityCheckBox?.isEnabled = !isTargetApplicationInheritOptions()
    }

    @objc func applicationCompatibilityToggle(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smoothAppCompatibility = sender.state == .on
        syncViewWithOptions()
        onOptionsChanged?()
    }

    private func installApplicationCompatibilityControl() {
        guard let anchor = verticalSmoothCheckBox,
              let bottom = view.constraints.first(where: {
                  $0.firstItem as? NSView === view && $0.firstAttribute == .bottom && $0.secondItem is NSTextField
              }), let caption = bottom.secondItem as? NSView else { return }
        let button = NSButton(checkboxWithTitle: NSLocalizedString("Application compatibility scrolling", comment: "Application scroll adapters switch"),
                              target: self, action: #selector(applicationCompatibilityToggle(_:)))
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.toolTip = NSLocalizedString("Use compatible scroll events in supported apps. Smooth scrolling, reverse scrolling, and application settings still apply.", comment: "Application scroll adapters explanation")
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        bottom.isActive = false
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 12),
            button.leadingAnchor.constraint(equalTo: anchor.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: anchor.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: 20)
        ])
        applicationCompatibilityCheckBox = button
    }

    override func updatePreferredContentSize() {
        preferredContentSize = view.fittingSize
    }
}
