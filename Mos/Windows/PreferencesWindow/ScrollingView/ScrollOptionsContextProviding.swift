//
//  ScrollOptionsContextProviding.swift
//  Mos
//  Shared helpers for view controllers that operate on scroll options.
//  Created by Caldis on 10/25/2025.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

protocol ScrollOptionsContextProviding: AnyObject {
    var currentTargetApplication: Application? { get set }

    func getTargetApplicationScrollOptions() -> OPTIONS_SCROLL_DEFAULT
    func isTargetApplicationInheritOptions() -> Bool
}

extension ScrollOptionsContextProviding {
    func getTargetApplicationScrollOptions() -> OPTIONS_SCROLL_DEFAULT {
        if let application = currentTargetApplication, application.inherit == false {
            return application.scroll
        }
        return Options.shared.scroll
    }

    func isTargetApplicationInheritOptions() -> Bool {
        if let application = currentTargetApplication {
            return application.inherit
        }
        return false
    }

    func updateSmoothDependentControl(_ control: NSButton?, isOn: Bool) {
        // Keep the original sync logic shared between the preferences panel and the popover.
        let isNotInherit = !isTargetApplicationInheritOptions()
        let scroll = getTargetApplicationScrollOptions()
        control?.state = NSControl.StateValue(rawValue: isOn ? 1 : 0)
        control?.isEnabled = isNotInherit && scroll.smooth
    }

    func updateSimulateTrackpadControl(_ control: NSButton?) {
        let scroll = getTargetApplicationScrollOptions()
        updateSmoothDependentControl(control, isOn: scroll.smoothSimTrackpad)
    }

    func updateReverseDependentControl(_ control: NSButton?, isOn: Bool) {
        let isNotInherit = !isTargetApplicationInheritOptions()
        let scroll = getTargetApplicationScrollOptions()
        control?.state = NSControl.StateValue(rawValue: isOn ? 1 : 0)
        control?.isEnabled = isNotInherit && scroll.reverse
    }
}
