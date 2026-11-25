import Cocoa

class ScrollSmoothDetailSettingsPopoverViewController: AdaptivePopover, ScrollOptionsContextProviding {

    @IBOutlet weak var verticalSmoothCheckBox: NSButton?
    @IBOutlet weak var horizontalSmoothCheckBox: NSButton?
    @IBOutlet weak var simulateTrackpadCheckBox: NSButton?
    @IBOutlet private weak var detailsFooter: NSTextField?
    @IBOutlet private var footerBottomConstraint: NSLayoutConstraint?
    private let noteWidth: CGFloat = 156
    private lazy var popoverWidthConstraint = view.widthAnchor.constraint(equalToConstant: 215)

    private lazy var normalizationCheckBox = NSButton(
        checkboxWithTitle: NSLocalizedString("scroll-screen-frame-clock", comment: "Experimental scroll timing normalization checkbox"),
        target: self, action: #selector(normalizationToggle(_:))
    )
    private lazy var normalizationView: NSStackView = {
        let note = NSLocalizedString("scroll-screen-frame-clock-description", comment: "Shared scroll rate with timing normalization")
        let stack = frameOption(normalizationCheckBox, note: note)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    var currentTargetApplication: Application?
    var onOptionsChanged: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        if let footer = detailsFooter {
            wrapNote(footer)
            simulateTrackpadCheckBox?.setAccessibilityHelp(footer.stringValue)
        }
        syncViewWithOptions()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncViewWithOptions()
    }

    override func updatePreferredContentSize() {
        var buttons = [verticalSmoothCheckBox, horizontalSmoothCheckBox, simulateTrackpadCheckBox]
        if normalizationView.superview != nil {
            buttons.append(normalizationCheckBox)
        }
        let buttonWidth = buttons.compactMap { $0?.intrinsicContentSize.width }.max() ?? 0
        // Titles determine the popover width. Supporting notes wrap in their own column.
        popoverWidthConstraint.constant = 40 + max(buttonWidth, 19 + noteWidth)
        popoverWidthConstraint.isActive = true
        preferredContentSize = view.fittingSize
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
        scrollOptions.smoothSimTrackpad = sender.state == .on
        syncViewWithOptions()
        onOptionsChanged?()
    }

    @objc private func normalizationToggle(_ sender: NSButton) {
        Options.shared.scrollNormalizeTiming = sender.state == .on
        onOptionsChanged?()
    }

    private func syncViewWithOptions() {
        updateSimulateTrackpadControl(simulateTrackpadCheckBox)
        if #unavailable(macOS 15.0) {
            simulateTrackpadCheckBox?.isEnabled = false
        }
        let scroll = getTargetApplicationScrollOptions()
        updateSmoothDependentControl(verticalSmoothCheckBox, isOn: scroll.smoothVertical)
        updateSmoothDependentControl(horizontalSmoothCheckBox, isOn: scroll.smoothHorizontal)
        syncNormalizationOption()
    }

    private func frameOption(_ button: NSButton, note: String) -> NSStackView {
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setAccessibilityHelp(note)

        let label = NSTextField(wrappingLabelWithString: note)
        label.font = detailsFooter?.font ?? .systemFont(ofSize: NSFont.systemFontSize(for: .mini))
        label.textColor = detailsFooter?.textColor ?? .secondaryLabelColor
        wrapNote(label)
        let indentedLabel = NSStackView(views: [label])
        indentedLabel.edgeInsets = NSEdgeInsets(top: 0, left: 19, bottom: 0, right: 0)

        let row = NSStackView(views: [button, indentedLabel])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 5
        return row
    }

    private func wrapNote(_ label: NSTextField) {
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = noteWidth
        label.widthAnchor.constraint(lessThanOrEqualToConstant: noteWidth).isActive = true
    }

    private func syncNormalizationOption() {
        guard let footer = detailsFooter, let bottom = footerBottomConstraint else { return }
        if currentTargetApplication != nil {
            if normalizationView.superview != nil {
                normalizationView.removeFromSuperview()
                bottom.isActive = true
            }
            return
        }
        if normalizationView.superview == nil {
            bottom.isActive = false
            view.addSubview(normalizationView)
            NSLayoutConstraint.activate([
                normalizationView.topAnchor.constraint(equalTo: footer.bottomAnchor, constant: 12),
                normalizationView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                normalizationView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                normalizationView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            ])
        }
        normalizationCheckBox.state = Options.shared.scrollNormalizeTiming ? .on : .off
        normalizationCheckBox.isEnabled = Options.shared.scroll.smooth
    }
}
