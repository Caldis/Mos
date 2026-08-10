//
//  MonitorViewController.swift
//  Mos
//  滚动监控界面
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa
import DGCharts

let scrollEventName = NSNotification.Name(rawValue: "ScrollEvent")
let buttonEventName = NSNotification.Name(rawValue: "ButtonEvent")

class MonitorViewController: NSViewController, ChartViewDelegate {

    private enum PreviewRefresh {
        static let buttonLogInterval: TimeInterval = 0.1
    }
    
    // MARK: - UI: 图表
    var lineChartCount = 0.0
    @IBOutlet weak var lineChart: LineChartView!
    
    // MARK: - UI: Log 文本
    @IBOutlet var parsedLogTextField: NSTextView!
    @IBOutlet var scrollLogTextField: NSTextView!
    @IBOutlet var scrollDetailLogTextField: NSTextView!
    @IBOutlet var buttonEventLogTextField: NSTextView!
    @IBOutlet var processLogTextField: NSTextView!
    @IBOutlet var mouseLogTextField: NSTextView!

    // MARK: - UI: 事件触发器
    @IBOutlet weak var shortcutMenu: NSMenu!
    @IBOutlet weak var shortcutPopUpButton: NSPopUpButton!

    // MARK: - 生命周期
    override func viewWillAppear() {
        initCharts()
        initScrollObserver()
        initButtonObserver()
        setupShortcutMenu()
    }
    override func viewWillDisappear() {
        uninitScrollObserver()
        uninitButtonObserver()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 监听: 滚动
    var scrollEventInterceptor: Interceptor?
    let scrollEventMask = ScrollCore.shared.scrollEventMask
    let scrollEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 发送 ScrollWheelEventUpdate 通知
        NotificationCenter.default.post(name: scrollEventName, object: event)
        // 返回事件对象
        return Unmanaged.passUnretained(event)
    }
    // 更新面板
    var prevScrollWheelEventScrollPhase = 0.0
    var prevScrollWheelEventMomentumPhase = 0.0
    @objc private func updateScrollEventData(notification: NSNotification) {
        let event = notification.object as! CGEvent
        // 更新图表
        if let data = lineChart.data {
            // scrollWheelEventPointDelta
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)), toDataSet: 0)
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)), toDataSet: 1)

            // scrollWheelEventIsContinuous
            let isContinuous = Double(event.getIntegerValueField(.scrollWheelEventIsContinuous))
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: isContinuous), toDataSet: 2)
            
            // scrollWheelEventScrollCount
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: Double(event.getIntegerValueField(.scrollWheelEventScrollCount))), toDataSet: 3)
            
            // scrollWheelEventScrollPhase
            let scrollPhase = Double(event.getIntegerValueField(.scrollWheelEventScrollPhase))
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: scrollPhase), toDataSet: 4)

            // scrollWheelEventMomentumPhase
            let momentumPhase = Double(event.getIntegerValueField(.scrollWheelEventMomentumPhase))
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: momentumPhase), toDataSet: 5)

            // Logs
            if prevScrollWheelEventScrollPhase != scrollPhase || prevScrollWheelEventMomentumPhase != momentumPhase {
                if prevScrollWheelEventScrollPhase != scrollPhase {
                    prevScrollWheelEventScrollPhase = scrollPhase
                }
                if prevScrollWheelEventMomentumPhase != momentumPhase {
                    prevScrollWheelEventMomentumPhase = momentumPhase
                }
                NSLog("Phase updated -> prevScrollWheelEventScrollPhase: \(scrollPhase), prevScrollWheelEventMomentumPhase: \(momentumPhase)")
            }

            lineChart.setVisibleXRange(minXRange: 1.0, maxXRange: 100.0)
            lineChart.moveViewToX(lineChartCount)
            lineChart.notifyDataSetChanged()
            lineChartCount += 1.0
        }
        // 更新 Log
        parsedLogTextField.string = Logger.getParsedLog(form: event)
        scrollLogTextField.string = Logger.getScrollLog(form: event)
        scrollDetailLogTextField.string = Logger.getScrollDetailLog(form: event)
        processLogTextField.string = Logger.getProcessLog(form: event)
        mouseLogTextField.string = Logger.getMouseLog(form: event)
    }
    // 初始化监听
    func initScrollObserver() {
        // 监听内部事件
        NotificationCenter.default.addObserver(self, selector: #selector(updateScrollEventData), name: scrollEventName, object: nil)
        // 启动事件拦截
        do {
            scrollEventInterceptor = try Interceptor(
                event: scrollEventMask,
                handleBy: scrollEventCallBack,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .listenOnly
            )
        } catch {
            NSLog("[MonitorView] Create scroll interceptor failure: \(error)")
        }
    }
    // 停止
    func uninitScrollObserver() {
        scrollEventInterceptor?.stop()
    }
    
    // MARK: - 监听: 按键
    var buttonEventInterceptor: Interceptor?
    var buttonEventMask: CGEventMask {
        let buttonDownEvents =
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let buttonUpEvents =
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let dragEvents =
            CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        let keyboardEvents =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let moveEvents = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        return buttonDownEvents | buttonUpEvents | dragEvents | keyboardEvents | moveEvents
    }
    let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 发送按钮事件通知
        NotificationCenter.default.post(name: buttonEventName, object: event)
        // 返回事件对象
        return Unmanaged.passUnretained(event)
    }
    // 按钮日志
    private let buttonEventLogStore = MonitorLogStore(previewLineLimit: 200)
    private var isButtonPreviewRefreshScheduled = false
    // 更新面板
    @objc private func updateButtonEventData(notification: NSNotification) {
        let event = notification.object as! CGEvent
        buttonEventLogStore.append(buttonEventLogLine(for: event), to: .buttonEvent)
        scheduleButtonPreviewRefresh()
    }

    func buttonEventLogLine(for event: CGEvent) -> String {
        let modifiers = event.modifierString.isEmpty ? "none" : event.modifierString
        let flagsHex = String(event.flags.rawValue, radix: 16)

        if event.isMouseInteractionEvent {
            let userData = event.getIntegerValueField(.eventSourceUserData)
            let deltaX = Int(event.getDoubleValueField(.mouseEventDeltaX))
            let deltaY = Int(event.getDoubleValueField(.mouseEventDeltaY))
            return "[\(event.timestampFormatted)] \(event.eventTypeName) button: \(event.mouseCode) delta:(\(deltaX),\(deltaY)) mods:[\(modifiers)] flags:0x\(flagsHex) userData: \(userData)"
        }

        if event.type == .flagsChanged {
            let phase = event.isKeyDown ? "down" : "up"
            return "[\(event.timestampFormatted)] \(event.eventTypeName) key: \(event.keyCodeName) phase: \(phase) mods:[\(modifiers)] flags:0x\(flagsHex)"
        }

        if event.isKeyboardEvent {
            return "[\(event.timestampFormatted)] \(event.eventTypeName) key: \(event.keyCodeName) keyCode: \(event.keyCode) mods:[\(modifiers)] flags:0x\(flagsHex)"
        }

        return "[\(event.timestampFormatted)] \(event.eventTypeName) \(event.displayName) flags:0x\(flagsHex)"
    }
    // 初始化
    func initButtonObserver() {
        // 监听内部事件
        NotificationCenter.default.addObserver(self, selector: #selector(updateButtonEventData), name: buttonEventName, object: nil)
        // 启动事件拦截
        do {
            buttonEventInterceptor = try Interceptor(
                event: buttonEventMask,
                handleBy: buttonEventCallBack,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .listenOnly
            )
        } catch {
            NSLog("[MonitorView] Create button interceptor failure: \(error)")
        }
    }
    // 停止
    func uninitButtonObserver() {
        buttonEventInterceptor?.stop()
    }

    private func scheduleButtonPreviewRefresh() {
        guard !isButtonPreviewRefreshScheduled else { return }
        isButtonPreviewRefreshScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + PreviewRefresh.buttonLogInterval) { [weak self] in
            guard let self else { return }
            self.isButtonPreviewRefreshScheduled = false
            self.refreshButtonLogPreview()
        }
    }

    private func refreshButtonLogPreview() {
        guard let textView = buttonEventLogTextField else { return }
        textView.string = buttonEventLogStore.previewText(for: .buttonEvent)
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    @IBAction private func exportButtonEventLog(_ sender: Any) {
        guard let window = view.window else { return }

        let savePanel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        savePanel.nameFieldStringValue = "monitor-button-events-\(formatter.string(from: Date())).log"
        savePanel.allowedFileTypes = ["log", "txt"]

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else { return }
            let output = self.buttonEventLogStore.exportText(for: .buttonEvent)
            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("[MonitorView] Export button event log failure: \(error)")
            }
        }
    }

    // MARK: - 按键事件处理
    func setupShortcutMenu() {
        guard shortcutMenu != nil else {
            NSLog("[MonitorView] shortcutMenu 未连接，无法构建菜单")
            return
        }

        // 使用 ShortcutManager 构建分级菜单
        ShortcutManager.buildShortcutMenu(
            into: shortcutMenu,
            target: self,
            action: #selector(onShortcutMenuItemSelected(_:))
        )

        // 设置默认选择 placeholder
        shortcutPopUpButton?.selectItem(at: 0)
    }
    @objc func onShortcutMenuItemSelected(_ sender: NSMenuItem) {
        guard let shortcut = sender.representedObject as? SystemShortcut.Shortcut else {
            NSLog("[MonitorView] 无法获取快捷键信息")
            return
        }
        // 使用 ShortcutExecutor 触发快捷键
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ShortcutExecutor.shared.execute(shortcut)
        }
    }
    

    // MARK: - 图表管理
    // 初始化
    func initCharts() {
        // 定义颜色
        let green = NSUIColor(red: 96.0/255.0, green: 198.0/255.0, blue: 85.0/255.0, alpha: 1.0)
        let yellow = NSUIColor(red: 246.0/255.0, green: 191.0/255.0, blue: 79.0/255.0, alpha: 1.0)
        let blue = NSUIColor(red: 52.0/255.0, green: 152.0/255.0, blue: 219.0/255.0, alpha: 1.0)
        let purple = NSUIColor(red: 155.0/255.0, green: 89.0/255.0, blue: 182.0/255.0, alpha: 1.0)
        let orange = NSUIColor(red: 230.0/255.0, green: 126.0/255.0, blue: 34.0/255.0, alpha: 1.0)
        let red = NSUIColor(red: 231.0/255.0, green: 76.0/255.0, blue: 60.0/255.0, alpha: 1.0)
        
        // 设置代理
        lineChart.delegate = self
        // 初始化图表数据
        lineChartCount = 0.0
        
        // 设置数据集
        let verticalData = LineChartDataSet(entries: [ChartDataEntry(x: 0.0, y: 0.0)], label: "Vertical")
        verticalData.valueTextColor = NSColor.labelColor
        verticalData.colors = [green]
        verticalData.circleRadius = 1.5
        verticalData.circleColors = [green]
        
        let horizontalData = LineChartDataSet(entries: [ChartDataEntry(x: 0.0, y: 0.0)], label: "Horizontal")
        horizontalData.valueTextColor = NSColor.labelColor
        horizontalData.colors = [yellow]
        horizontalData.circleRadius = 1.5
        horizontalData.circleColors = [yellow]
        
        let isContinuousData = LineChartDataSet(entries: [ChartDataEntry(x: 0.0, y: 0.0)], label: "IsContinuous")
        isContinuousData.valueTextColor = NSColor.labelColor
        isContinuousData.colors = [blue]
        isContinuousData.circleRadius = 1.5
        isContinuousData.circleColors = [blue]
        
        let scrollCountData = LineChartDataSet(entries: [ChartDataEntry(x: 0.0, y: 0.0)], label: "ScrollCount")
        scrollCountData.valueTextColor = NSColor.labelColor
        scrollCountData.colors = [purple]
        scrollCountData.circleRadius = 1.5
        scrollCountData.circleColors = [purple]
        
        let scrollPhaseData = LineChartDataSet(entries: [ChartDataEntry(x: 0.0, y: 0.0)], label: "ScrollPhase")
        scrollPhaseData.valueTextColor = NSColor.labelColor
        scrollPhaseData.colors = [orange]
        scrollPhaseData.circleRadius = 1.5
        scrollPhaseData.circleColors = [orange]
        
        let momentumPhaseData = LineChartDataSet(entries: [ChartDataEntry(x: 0.0, y: 0.0)], label: "MomentumPhase")
        momentumPhaseData.valueTextColor = NSColor.labelColor
        momentumPhaseData.colors = [red]
        momentumPhaseData.circleRadius = 1.5
        momentumPhaseData.circleColors = [red]
        
        lineChart.data = LineChartData(dataSets: [verticalData, horizontalData, isContinuousData, scrollCountData, scrollPhaseData, momentumPhaseData])
        
        // 设置图表样式
        lineChart.noDataTextColor = NSColor.labelColor
        lineChart.chartDescription.text = ""
        lineChart.legend.textColor = NSColor.labelColor
        lineChart.xAxis.labelTextColor = NSColor.labelColor
        lineChart.leftAxis.labelTextColor = NSColor.labelColor
        lineChart.rightAxis.labelTextColor = NSColor.labelColor
        lineChart.drawBordersEnabled = true
        lineChart.borderColor = NSColor.secondaryLabelColor
    }
    // 刷新内容
    @IBAction func refreshChart(_ sender: Any) {
        initCharts()
        // 清空按钮事件日志
        buttonEventLogStore.clear(.buttonEvent)
        isButtonPreviewRefreshScheduled = false
        buttonEventLogTextField?.string = ""
    }
}
