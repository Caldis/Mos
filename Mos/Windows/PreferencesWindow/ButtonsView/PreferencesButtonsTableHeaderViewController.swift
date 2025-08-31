//
//  TableHeader.swift
//  Mos
//
//  Created by 陈标 on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import AppKit

class ButtonsTableHeaderViewController: NSTableHeaderView {
    
    override func awakeFromNib() {
        // 设置表头高度为0以隐藏
        self.frame.size.height = 0
    }
}
