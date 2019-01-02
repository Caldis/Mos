//
//  PreferencesTabViewItem.swift
//  Mos
//
//  Created by Caldis on 2019/1/2.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class PreferencesTabViewItem: NSTabViewItem {
    
    override func sizeOfLabel(_ computeMin: Bool) -> NSSize {
        var size = super.sizeOfLabel(computeMin)
        size.width = 100.0
        return size
    }
    
}
