//
//  PreferencesContributorsViewController.swift
//  Mos
//  贡献者名单
//  Created by Caldis on 2018/7/9.
//  Copyright © 2018 Caldis. All rights reserved.
//

import Cocoa

class PreferencesContributorsViewController: NSViewController {
    
    // 打开 Paypal 捐赠链接
    @IBAction func contributorsListClick(_ sender: NSButtonCell) {
        if let url = URL(string: "https://github.com/Caldis/Mos/graphs/contributors") {
            NSWorkspace.shared.open(url)
        }
    }
    
}
