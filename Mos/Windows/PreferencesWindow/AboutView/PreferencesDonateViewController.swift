//
//  PreferencesDonateViewCOntroller.swift
//  Mos
//  捐赠界面
//  Created by Caldis on 2017/1/27.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesDonateViewController: NSViewController {
    
    // Constants
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!
    
    // 打开肥猫链接
    @IBAction func fatCatClick(_ sender: NSButton) {
        if let url = URL(string: "https://meow.caldis.me?from=MosApplication&version=\(version as! String)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // 打开 Paypal 捐赠链接
    @IBAction func donateByPaypalClick(_ sender: NSButtonCell) {
        if let url = URL(string: "https://www.paypal.me/mosapp") {
            NSWorkspace.shared.open(url)
        }
    }
    
}
