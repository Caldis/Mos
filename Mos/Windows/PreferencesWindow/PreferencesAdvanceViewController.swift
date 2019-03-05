//
//  PreferencesAdvanceViewController.swift
//  Mos
//  高级选项界面
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAdvanceViewController: NSViewController {
    
    @IBOutlet weak var toggleKeyPopUpButton: NSPopUpButton!
    @IBOutlet weak var disableKeyPopUpButton: NSPopUpButton!
    @IBOutlet weak var scrollStepSlider: NSSlider!
    @IBOutlet weak var scrollStepInput: NSTextField!
    @IBOutlet weak var scrollStepStepper: NSStepper!
    @IBOutlet weak var scrollSpeedSlider: NSSlider!
    @IBOutlet weak var scrollSpeedInput: NSTextField!
    @IBOutlet weak var scrollSpeedStepper: NSStepper!
    @IBOutlet weak var scrollDurationSlider: NSSlider!
    @IBOutlet weak var scrollDurationInput: NSTextField!
    @IBOutlet weak var scrollDurationStepper: NSStepper!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 读取设置
        syncViewWithOptions()
    }
    
    // 转换
    @IBAction func toggleKeyPopUpButtonChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        Options.shared.advanced.toggle = Int(index>1 ? MODIFIER_KEY.list[index-2] : 0)
    }
    // 禁用
    @IBAction func disableKeyPopUpButtonChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        Options.shared.advanced.block = Int(index>1 ? MODIFIER_KEY.list[index-2] : 0)
    }
    
    // 步长
    @IBAction func scrollStepSliderChange(_ sender: NSSlider) {
        setScrollStep(value: sender.doubleValue)
    }
    @IBAction func scrollStepInputChange(_ sender: NSTextField) {
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
    @IBAction func scrollSpeedInputChange(_ sender: NSTextField) {
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
    @IBAction func scrollDurationInputChange(_ sender: NSTextField) {
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
    
}

/**
 * 设置同步
 **/
extension PreferencesAdvanceViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 转换
        if let index = MODIFIER_KEY.list.index(of: CGKeyCode(Options.shared.advanced.toggle)) {
            toggleKeyPopUpButton.selectItem(at: index+2)
        } else {
            toggleKeyPopUpButton.selectItem(at: 0)
        }
        // 禁用
        if let index = MODIFIER_KEY.list.index(of: CGKeyCode(Options.shared.advanced.block)) {
            disableKeyPopUpButton.selectItem(at: index+2)
        } else {
            disableKeyPopUpButton.selectItem(at: 0)
        }
        // 步长
        let step = Options.shared.advanced.step
        scrollStepSlider.doubleValue = step
        scrollStepStepper.doubleValue = step
        scrollStepInput.stringValue = String(format: "%.2f", step)
        // 速度
        let speed = Options.shared.advanced.speed
        scrollSpeedSlider.doubleValue = speed
        scrollSpeedStepper.doubleValue = speed
        scrollSpeedInput.stringValue = String(format: "%.2f", speed)
        // 过渡
        let duration = Options.shared.advanced.duration
        scrollDurationSlider.doubleValue = duration
        scrollDurationStepper.doubleValue = duration
        scrollDurationInput.stringValue = String(format: "%.2f", duration)
    }
}
