//
//  PreferencesDonateViewCOntroller.swift
//  Mos
//  捐助二维码界面
//  Created by Caldis on 2017/1/27.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesDonateViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    @IBAction func donateByPaypalClick(_ sender: NSButtonCell) {
        if let url = URL(string: "https://www.paypal.me/mosapp") {
            NSWorkspace.shared.open(url)
        }
    }
}
