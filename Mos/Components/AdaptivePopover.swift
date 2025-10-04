//
//  AdaptivePopover.swift
//  Mos
//  Popover tip view that auto-sizes based on content
//  Created by Caldis on 2025/10/03.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class AdaptivePopover: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        updatePreferredContentSize()
    }

    private func updatePreferredContentSize() {
        guard let contentView = view.subviews.first else { return }

        // Calculate the intrinsic size of the first subview
        let contentSize = contentView.intrinsicContentSize

        // Add padding (12pt horizontal, 10pt vertical based on constraints)
        let width = contentSize.width + 24
        let height = contentSize.height + 20

        // Update preferred content size for the popover
        preferredContentSize = NSSize(width: width, height: height)
    }

}
