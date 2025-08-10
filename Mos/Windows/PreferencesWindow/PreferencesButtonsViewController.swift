//
//  PreferencesButtonsViewController.swift
//  Mos
//  按钮绑定配置界面
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesButtonsViewController: NSViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 读取设置
        syncViewWithOptions()
    }
}

/**
 * 设置同步
 **/
extension PreferencesButtonsViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // TODO: 实现按钮相关设置的同步逻辑
    }
}
