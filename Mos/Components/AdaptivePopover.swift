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

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    func updatePreferredContentSize() {
        view.layoutSubtreeIfNeeded()

        let subviews = view.subviews

        let contentView = subviews.first!
        var contentSize = contentView.intrinsicContentSize
        if contentSize.equalTo(.zero) {
            contentSize = contentView.fittingSize
        }

        // Add padding (12pt horizontal, 10pt vertical based on constraints)
        let width = contentSize.width + 24
        let height = contentSize.height + 20

        preferredContentSize = NSSize(width: width, height: height)
    }

}
