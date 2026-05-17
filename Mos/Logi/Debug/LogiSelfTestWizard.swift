//
//  LogiSelfTestWizard.swift
//  Mos
//
//  DEBUG-only AppKit window hosting the Logi Self-Test Wizard. Drives the
//  Step list returned by LogiSelfTestRunner one step at a time with
//  Run / Skip / Next controls. Handles automatic + physicalAutoVerified
//  step kinds; physicalUserConfirmed is a future TODO.
//

#if DEBUG
import Cocoa

final class LogiSelfTestWizard {

    static let shared = LogiSelfTestWizard()
    private init() {}

    private var window: NSWindow?
    private let runner = LogiSelfTestRunner()
    private var steps: [Step] = []
    private var currentIndex = 0
    private var lastOutcome: StepOutcome?

    private var headerLabel: NSTextField?
    private var instructionLabel: NSTextField?
    private var expectationLabel: NSTextField?
    private var statusLabel: NSTextField?
    private var runButton: NSButton?
    private var skipButton: NSButton?
    private var nextButton: NSButton?
    private var pendingObserver: NSObjectProtocol?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        steps = runner.buildBoltSuite()    // future: detect + pick suite
        currentIndex = 0
        lastOutcome = nil
        buildWindow()
        renderCurrent()
    }

    private func buildWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "Logi Self-Test"
        win.center()
        win.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "")
        header.font = NSFont.boldSystemFont(ofSize: 14)
        headerLabel = header

        let instr = NSTextField(wrappingLabelWithString: "")
        instr.preferredMaxLayoutWidth = 420
        instructionLabel = instr

        let expect = NSTextField(wrappingLabelWithString: "")
        expect.preferredMaxLayoutWidth = 420
        expect.textColor = .secondaryLabelColor
        expect.font = NSFont.systemFont(ofSize: 11)
        expectationLabel = expect

        let statusRow = NSTextField(labelWithString: "")
        statusRow.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusLabel = statusRow

        let runBtn = NSButton(title: "Run", target: self, action: #selector(runClicked))
        let skipBtn = NSButton(title: "Skip", target: self, action: #selector(skipClicked))
        let nextBtn = NSButton(title: "Next", target: self, action: #selector(nextClicked))
        runButton = runBtn; skipButton = skipBtn; nextButton = nextBtn

        let buttonRow = NSStackView(views: [runBtn, skipBtn, nextBtn])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(instr)
        stack.addArrangedSubview(expect)
        stack.addArrangedSubview(statusRow)
        stack.addArrangedSubview(buttonRow)

        let contentView = NSView()
        contentView.addSubview(stack)
        win.contentView = contentView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    private func renderCurrent() {
        guard currentIndex < steps.count else {
            // All done — show summary.
            headerLabel?.stringValue = "Self-Test complete"
            instructionLabel?.stringValue = "All steps attempted."
            expectationLabel?.stringValue = ""
            statusLabel?.stringValue = ""
            runButton?.isHidden = true
            skipButton?.isHidden = true
            nextButton?.title = "Close"
            nextButton?.isEnabled = true
            return
        }
        let step = steps[currentIndex]
        headerLabel?.stringValue = "Step \(step.index) of \(step.total) \u{2014} \(step.title)"
        instructionLabel?.stringValue = step.instruction
        expectationLabel?.stringValue = "Expected: \(step.expectation)"
        statusLabel?.stringValue = ""
        statusLabel?.textColor = .labelColor
        runButton?.isHidden = false
        runButton?.isEnabled = true
        skipButton?.isHidden = false
        skipButton?.isEnabled = true
        nextButton?.title = "Next"
        nextButton?.isEnabled = false  // disabled until Run completes (or Skip)
    }

    @objc private func runClicked() {
        let step = steps[currentIndex]
        runButton?.isEnabled = false
        statusLabel?.stringValue = "Running\u{2026}"
        statusLabel?.textColor = .secondaryLabelColor
        switch step.kind {
        case .automatic(_, let run):
            run { [weak self] outcome in
                DispatchQueue.main.async { self?.handleOutcome(outcome) }
            }
        case .physicalAutoVerified(_, _, let wait, let timeout):
            startWait(wait, timeout: timeout)
        case .physicalUserConfirmed:
            // Not used in the minimal Bolt suite; treat as pass for now.
            handleOutcome(.pass)
        }
    }

    private func startWait(_ condition: WaitCondition, timeout: TimeInterval) {
        // For now, only handle .rawButtonEvent — sufficient for the example step.
        switch condition {
        case .rawButtonEvent(let mosCode, _):
            let token = NotificationCenter.default.addObserver(
                forName: LogiCenter.rawButtonEvent, object: nil, queue: .main
            ) { [weak self] notif in
                if let expected = mosCode, (notif.userInfo?["mosCode"] as? UInt16) != expected { return }
                self?.endWait()
                self?.handleOutcome(.pass)
            }
            pendingObserver = token
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self = self, self.pendingObserver != nil else { return }
                self.endWait()
                self.handleOutcome(.fail(reason: "Timed out after \(Int(timeout))s"))
            }
        default:
            // Other wait conditions are step-suite TODOs.
            handleOutcome(.fail(reason: "WaitCondition not yet implemented"))
        }
    }

    private func endWait() {
        if let token = pendingObserver {
            NotificationCenter.default.removeObserver(token)
            pendingObserver = nil
        }
    }

    private func handleOutcome(_ outcome: StepOutcome) {
        lastOutcome = outcome
        switch outcome {
        case .pass:
            statusLabel?.stringValue = "\u{2713} Passed"
            statusLabel?.textColor = NSColor.systemGreen
        case .fail(let reason):
            statusLabel?.stringValue = "\u{2717} Failed \u{2014} \(reason)"
            statusLabel?.textColor = NSColor.systemRed
        }
        nextButton?.isEnabled = true
    }

    @objc private func skipClicked() {
        endWait()
        statusLabel?.stringValue = "Skipped"
        statusLabel?.textColor = .secondaryLabelColor
        nextButton?.isEnabled = true
    }

    @objc private func nextClicked() {
        if currentIndex >= steps.count {
            window?.close()
            window = nil
            return
        }
        currentIndex += 1
        renderCurrent()
    }
}
#endif
