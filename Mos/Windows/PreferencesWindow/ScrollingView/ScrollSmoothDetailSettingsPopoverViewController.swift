//
//  SimulateTrackpadPopoverViewController.swift
//  Mos
//  Popover wrapper that reuses scroll option logic for the Simulate Trackpad feature.
//  Created by Caldis on 10/25/2025.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

class ScrollSmoothDetailSettingsPopoverViewController: AdaptivePopover, ScrollOptionsContextProviding {

    @IBOutlet weak var simulateTrackpadCheckBox: NSButton?
    @IBOutlet weak var vertivalSmooth: NSButton!
    @IBOutlet weak var horizontalSmooth: NSButton!

    var currentTargetApplication: Application?
    var onOptionsChanged: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
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

    @IBAction func simulateTrackpadToggle(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smoothSimTrackpad = sender.state == .on
        syncViewWithOptions()
        onOptionsChanged?()
    }

    @IBAction func verticalSmoothToggle(_ sender: NSButton) {
    }

    @IBAction func horizontalSmoothToggle(_ sender: NSButton) {
    }
    
    func syncViewWithOptions() {
        updateSimulateTrackpadControl(simulateTrackpadCheckBox)
    }
}
