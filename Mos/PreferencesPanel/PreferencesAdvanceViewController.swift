//
//  PreferencesAdvanceViewController.swift
//  Mos
//  高级选项界面
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAdvanceViewController: NSViewController {
    
    @IBOutlet weak var scrollSpeedSlider: NSSlider!
    @IBOutlet weak var scrollSpeedLabel: NSTextField!
    @IBOutlet weak var scrollSpeedStepper: NSStepper!
    @IBOutlet weak var scrollTransitionSlider: NSSlider!
    @IBOutlet weak var scrollTransitionLabel: NSTextField!
    @IBOutlet weak var scrollTransitionStepper: NSStepper!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 恢复设置
        syncViewWithOptions()
    }
    
    // 速度
    @IBAction func scrollSpeedSliderChange(_ sender: NSSlider) {
        setScrollSpeed(value: sender.doubleValue)
    }
    @IBAction func scrollSpeedStepperChange(_ sender: NSStepper) {
        setScrollSpeed(value: sender.doubleValue)
    }
    func setScrollSpeed(value: Double) {
        Options.shared.current.advanced.speed = value
        syncViewWithOptions()
    }
    
    // 过渡
    @IBAction func scrollTransitionSliderChange(_ sender: NSSlider) {
        setScrollTransition(value: sender.doubleValue)
    }
    @IBAction func scrollTransitionStepperChange(_ sender: NSStepper) {
        setScrollTransition(value: sender.doubleValue)
    }
    func setScrollTransition(value: Double) {
        Options.shared.current.advanced.transition = value
        syncViewWithOptions()
    }
    
    // 重置
    @IBAction func resetToDefaultClick(_ sender: NSButton) {
        Options.shared.current.advanced = Options.DEFAULT_OPTIONS.advanced
        syncViewWithOptions()
    }
    
    // 同步界面与设置参数
    func syncViewWithOptions() {
        // 速度
        let speed = Options.shared.current.advanced.speed
        scrollSpeedSlider.doubleValue = speed
        scrollSpeedStepper.doubleValue = speed
        scrollSpeedLabel.stringValue = String(format: "%.2f", speed)
        // 过渡
        let transition = Options.shared.current.advanced.transition
        scrollTransitionSlider.doubleValue = transition
        scrollTransitionStepper.doubleValue = transition
        scrollTransitionLabel.stringValue = String(format: "%.2f", transition)
    }
    
}
