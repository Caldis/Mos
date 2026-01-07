//
//  PreferencesUpdatesViewController.swift
//  Mos
//  更新界面
//  Created by Caldis on 2017/1/21.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesUpdatesViewController: NSViewController {
    
    // UI Elements
    // 版本号
    @IBOutlet weak var versionLabel: NSTextField!
    @IBOutlet weak var checkOnAppStartCheckbox: NSButton!
    @IBOutlet weak var includingBetaVersionCheckbox: NSButton!
    
    override func viewDidLoad() {
        // 版本号
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")!
        versionLabel.stringValue = "\(NSLocalizedString("Current Version", comment: "")): \(version as! String) · \(build as! String)"

        checkOnAppStartCheckbox.state = Options.shared.update.checkOnAppStart ? .on : .off
        includingBetaVersionCheckbox.state = Options.shared.update.includingBetaVersion ? .on : .off
    }
    
    // 查询更新
    @IBAction func checkButtonClick(_ sender: NSButton) {
        UpdateManager.shared.checkForUpdates()
    }
    @IBAction func checkOnAppStartClick(_ sender: NSButton) {
        Options.shared.update.checkOnAppStart = sender.state == .on
    }
    @IBAction func includingBetaVersionClick(_ sender: NSButtonCell) {
        Options.shared.update.includingBetaVersion = sender.state == .on
    }
    
}
