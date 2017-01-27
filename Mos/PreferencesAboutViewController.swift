//
//  PreferencesAboutViewController.swift
//  Mos
//
//  Created by Cb on 2017/1/21.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class PreferencesAboutViewController: NSViewController {

    // 国际化相关
    let HomePageButtonTitle = NSLocalizedString("HomePage", comment: "")
    let CorrentVersionLabelTitle = NSLocalizedString("Corrent Version", comment: "")
    
    @IBOutlet weak var homePageButton: NSButtonCell!
    @IBOutlet weak var versionLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 获取一下版本号
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!
        versionLabel.stringValue = "\(CorrentVersionLabelTitle) : \(version as! String)"
        // 设置按钮属性
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        homePageButton.attributedTitle = NSAttributedString(string: HomePageButtonTitle, attributes: [NSForegroundColorAttributeName : NSColor.white, NSParagraphStyleAttributeName : paragraphStyle])
    }
    
}
