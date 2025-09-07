//
//  PreferencesAdvanceViewController.swift
//  Mos
//  高级选项界面
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAdvanceViewController: NSViewController {
    
    // Target application
    var currentTargetApplication: ExceptionalApplication?
    // UI Elements
    @IBOutlet weak var scrollSmoothCheckBox: NSButton!
    @IBOutlet weak var scrollReverseCheckBox: NSButton!
    @IBOutlet weak var dashKeyPopUpButton: NSPopUpButton!
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
    @IBOutlet weak var resetToDefaultsButton: NSButton!
    // Constants
    let PopUpButtonPadding = 2 // 减去第一个 Disabled 和分割线的距离
    let DefaultConfigForCompare = OPTIONS_SCROLL_DEFAULT()
    
    override func viewDidLoad() {
        // 禁止自动 Focus
        scrollStepInput.refusesFirstResponder = true
        scrollSpeedInput.refusesFirstResponder = true
        scrollDurationInput.refusesFirstResponder = true
        // 读取设置
        syncViewWithOptions()
    }
    
    // 平滑
    @IBAction func scrollSmoothClick(_ sender: NSButton) {
        Options.shared.scroll.smooth = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 翻转
    @IBAction func scrollReverseClick(_ sender: NSButton) {
        Options.shared.scroll.reverse = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
    
    // 加速
    @IBAction func dashKeyPopUpButtonChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        getTargetApplicationScrollOptions().dash = Int(index>1 ? MODIFIER_KEY_SET.all.codes[index-PopUpButtonPadding] : 0)
        syncViewWithOptions()
    }
    // 转换
    @IBAction func toggleKeyPopUpButtonChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        getTargetApplicationScrollOptions().toggle = Int(index>1 ? MODIFIER_KEY_SET.all.codes[index-PopUpButtonPadding] : 0)
        syncViewWithOptions()
    }
    // 禁用
    @IBAction func disableKeyPopUpButtonChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        getTargetApplicationScrollOptions().block = Int(index>1 ? MODIFIER_KEY_SET.all.codes[index-PopUpButtonPadding] : 0)
        syncViewWithOptions()
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
        getTargetApplicationScrollOptions().step = value
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
        getTargetApplicationScrollOptions().speed = value
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
        getTargetApplicationScrollOptions().duration = value
        syncViewWithOptions()
    }
    
    // 重置
    @IBAction func resetToDefaultClick(_ sender: NSButton) {
        if let target = currentTargetApplication {
            target.scroll = OPTIONS_SCROLL_DEFAULT()
        } else {
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        }
        syncViewWithOptions()
    }
    
}

/**
 * 工具函数
 **/
extension PreferencesAdvanceViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 是否继承配置
        let isNotInherit = !isTargetApplicationInheritOptions()
        // 滚动配置
        let scroll = getTargetApplicationScrollOptions()
        // 平滑
        scrollSmoothCheckBox.state = NSControl.StateValue(rawValue: scroll.smooth ? 1 : 0)
        scrollSmoothCheckBox.isEnabled = isNotInherit
        // 翻转
        scrollReverseCheckBox.state = NSControl.StateValue(rawValue: scroll.reverse ? 1 : 0)
        scrollReverseCheckBox.isEnabled = isNotInherit
        // 加速
        if let index = MODIFIER_KEY_SET.all.codes.firstIndex(of: CGKeyCode(scroll.dash ?? 0)) {
            dashKeyPopUpButton.selectItem(at: index+PopUpButtonPadding)
        } else {
            dashKeyPopUpButton.selectItem(at: 0)
        }
        dashKeyPopUpButton.isEnabled = isNotInherit
        // 转换
        if let index = MODIFIER_KEY_SET.all.codes.firstIndex(of: CGKeyCode(scroll.toggle ?? 0)) {
            toggleKeyPopUpButton.selectItem(at: index+PopUpButtonPadding)
        } else {
            toggleKeyPopUpButton.selectItem(at: 0)
        }
        toggleKeyPopUpButton.isEnabled = isNotInherit
        // 禁用
        if let index = MODIFIER_KEY_SET.all.codes.firstIndex(of: CGKeyCode(scroll.block ?? 0)) {
            disableKeyPopUpButton.selectItem(at: index+PopUpButtonPadding)
        } else {
            disableKeyPopUpButton.selectItem(at: 0)
        }
        disableKeyPopUpButton.isEnabled = isNotInherit
        // 步长
        let step = scroll.step
        scrollStepSlider.doubleValue = step
        scrollStepSlider.isEnabled = isNotInherit
        scrollStepStepper.doubleValue = step
        scrollStepStepper.isEnabled = isNotInherit
        scrollStepInput.stringValue = String(format: "%.2f", step)
        scrollStepInput.isEnabled = isNotInherit
        // 速度
        let speed = scroll.speed
        scrollSpeedSlider.doubleValue = speed
        scrollSpeedSlider.isEnabled = isNotInherit
        scrollSpeedStepper.doubleValue = speed
        scrollSpeedStepper.isEnabled = isNotInherit
        scrollSpeedInput.stringValue = String(format: "%.2f", speed)
        scrollSpeedInput.isEnabled = isNotInherit
        // 过渡
        let duration = scroll.duration
        scrollDurationSlider.doubleValue = duration
        scrollDurationSlider.isEnabled = isNotInherit
        scrollDurationStepper.doubleValue = duration
        scrollDurationStepper.isEnabled = isNotInherit
        scrollDurationInput.stringValue = String(format: "%.2f", duration)
        scrollDurationInput.isEnabled = isNotInherit
        // 初始化
        resetToDefaultsButton.isEnabled = isNotInherit && scroll != DefaultConfigForCompare
    }
    // 获取配置目标 (公共或应用配置)
    func getTargetApplicationScrollOptions() -> OPTIONS_SCROLL_DEFAULT {
        if let validCurrentTargetApplication = currentTargetApplication, validCurrentTargetApplication.inherit == false  {
            return validCurrentTargetApplication.scroll
        }
        return Options.shared.scroll
    }
    // 是否继承全局设置
    func isTargetApplicationInheritOptions() -> Bool {
        if let validCurrentTargetApplication = currentTargetApplication {
            return validCurrentTargetApplication.inherit
        }
        return false
    }
}
