//
//  PreferencesUpdatesViewController.swift
//  Mos
//
//  Created by Cb on 2017/1/21.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class PreferencesUpdatesViewController: NSViewController {

    // 国际化相关
    let CorrentVersionLabelTitle = NSLocalizedString("Corrent Version", comment: "")
    
    @IBOutlet weak var versionLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 获取一下版本号
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!
        versionLabel.stringValue = "\(CorrentVersionLabelTitle) : \(version as! String)"
    }
    
    @IBAction func checkButtonClick(_ sender: NSButton) {
        NSWorkspace.shared().open(URL(string: "https://github.com/Caldis/Mos/releases/")!)
    }
}
