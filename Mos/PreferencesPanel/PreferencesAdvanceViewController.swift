//
//  PreferencesAdvanceViewController.swift
//  Mos
//  高级选项界面
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAdvanceViewController: NSViewController {
    
    @IBOutlet weak var scrollTransitionSlider: NSSlider!
    @IBOutlet weak var scrollTransitionLabel: NSTextField!
    @IBOutlet weak var scrollTransitionStepper: NSStepper!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 恢复设置
        scrollTransitionSlider.doubleValue = Options.shared.current.advanced.lerp
        scrollTransitionLabel.stringValue = String(format: "%.2f", Options.shared.current.advanced.lerp)
        scrollTransitionStepper.doubleValue = Options.shared.current.advanced.lerp
    }
    
    // 过渡设置
    @IBAction func scrollTransitionSliderChange(_ sender: NSSlider) {
        setScrollTransition(value: sender.doubleValue)
    }
    @IBAction func scrollTransitionStepperChange(_ sender: NSStepper) {
        setScrollTransition(value: sender.doubleValue)
    }
    func setScrollTransition(value: Double) {
        // 修改Slider
        scrollTransitionSlider.doubleValue = value
        // 修改Stepper
        scrollTransitionStepper.doubleValue = value
        // 修改文字
        scrollTransitionLabel.stringValue = String(format: "%.2f", value)
        // 修改实际参数
        Options.shared.current.advanced.lerp = value
    }
    
    // 重置
    @IBAction func resetAllToDefaultClick(_ sender: NSButton) {
        scrollTransitionSlider.doubleValue = Options.DEFAULT_OPTIONS.advanced.lerp
        scrollTransitionStepper.doubleValue = Options.DEFAULT_OPTIONS.advanced.lerp
        scrollTransitionLabel.stringValue = String(format: "%.2f", Options.DEFAULT_OPTIONS.advanced.lerp)
        setScrollTransition(value: Options.DEFAULT_OPTIONS.advanced.lerp)
    }
}
