//
//  AddButton.swift
//  Mos
//
//  Created by 陈标 on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import AppKit

class AddButton: PrimaryButton {
    
    public var onMouseDown: ((AddButton) -> Void)?
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onMouseDown?(self)
    }
}
