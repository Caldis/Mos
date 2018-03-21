//
//  PreferencesAdvanceViewController.swift
//  Mos
//  高级选项界面
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAdvanceViewController: NSViewController {
    
    @IBOutlet weak var scrollStepSlider: NSSlider!
    @IBOutlet weak var scrollStepLabel: NSTextField!
    @IBOutlet weak var scrollStepStepper: NSStepper!
    @IBOutlet weak var scrollSpeedSlider: NSSlider!
    @IBOutlet weak var scrollSpeedLabel: NSTextField!
    @IBOutlet weak var scrollSpeedStepper: NSStepper!
    @IBOutlet weak var scrollDurationSlider: NSSlider!
    @IBOutlet weak var scrollDurationLabel: NSTextField!
    @IBOutlet weak var scrollDurationStepper: NSStepper!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 读取设置
        syncViewWithOptions()
    }
    
    // 步长
    @IBAction func scrollStepSliderChange(_ sender: NSSlider) {
        setScrollStep(value: sender.doubleValue)
    }
    @IBAction func scrollStepStepperChange(_ sender: NSStepper) {
        setScrollStep(value: sender.doubleValue)
    }
    func setScrollStep(value: Double) {
        Options.shared.advanced.step = value
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
        Options.shared.advanced.speed = value
        syncViewWithOptions()
    }
    
    // 过渡
    @IBAction func scrollDurationSliderChange(_ sender: NSSlider) {
        setScrollDuration(value: sender.doubleValue)
    }
    @IBAction func scrollDurationStepperChange(_ sender: NSStepper) {
        setScrollDuration(value: sender.doubleValue)
    }
    func setScrollDuration(value: Double) {
        Options.shared.advanced.duration = value
        syncViewWithOptions()
    }
    
    // 重置
    @IBAction func resetToDefaultClick(_ sender: NSButton) {
        Options.shared.advanced = Options.DEFAULT_OPTIONS.advanced
        syncViewWithOptions()
    }
    
    // 同步界面与设置
    func syncViewWithOptions() {
        // 步长
        let step = Options.shared.advanced.step
        scrollStepSlider.doubleValue = step
        scrollStepStepper.doubleValue = step
        scrollStepLabel.stringValue = String(format: "%.2f", step)
        // 速度
        let speed = Options.shared.advanced.speed
        scrollSpeedSlider.doubleValue = speed
        scrollSpeedStepper.doubleValue = speed
        scrollSpeedLabel.stringValue = String(format: "%.2f", speed)
        // 过渡
        let duration = Options.shared.advanced.duration
        scrollDurationSlider.doubleValue = duration
        scrollDurationStepper.doubleValue = duration
        scrollDurationLabel.stringValue = String(format: "%.2f", duration)
    }
    
}
