//
//  PreferencesDonateViewCOntroller.swift
//  Mos
//
//  Created by Cb on 2017/1/27.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class PreferencesDonateViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    @IBAction func donateByPaypalClick(_ sender: NSButtonCell) {
        if let url = URL(string: "https://www.paypal.me/mosapp") {
            NSWorkspace.shared().open(url)
        }
    }
}
