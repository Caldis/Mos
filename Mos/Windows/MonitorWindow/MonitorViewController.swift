//
//  MonitorViewController.swift
//  Mos
//  滚动监控界面
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa
import Charts

let scrollEventName = NSNotification.Name(rawValue: "ScrollEvent")
let buttonEventName = NSNotification.Name(rawValue: "ButtonEvent")

class MonitorViewController: NSViewController, ChartViewDelegate {
    
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
    
    // MARK: - 生命周期
    override func viewWillAppear() {
        initCharts()
        initScrollObserver()
        initButtonObserver()
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
    @objc private func updateScrollEventData(notification: NSNotification) {
        let event = notification.object as! CGEvent
        // 更新图表
        if let data = lineChart.data {
            // 原有的两个轴数据
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)), toDataSet: 0)
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)), toDataSet: 1)
            
            // 新增的四个字段
            // scrollWheelEventIsContinuous (转换为数值：连续=1，非连续=0)
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 ? 1.0 : 0.0
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: isContinuous), toDataSet: 2)
            
            // scrollWheelEventScrollCount
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: Double(event.getIntegerValueField(.scrollWheelEventScrollCount))), toDataSet: 3)
            
            // scrollWheelEventScrollPhase
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: Double(event.getIntegerValueField(.scrollWheelEventScrollPhase))), toDataSet: 4)
            
            // scrollWheelEventMomentumPhase
            data.appendEntry(ChartDataEntry(x: lineChartCount, y: Double(event.getIntegerValueField(.scrollWheelEventMomentumPhase))), toDataSet: 5)
            
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
        ButtonCore.shared.leftDown |
        ButtonCore.shared.rightDown |
        ButtonCore.shared.otherDown |
        ButtonCore.shared.keyDown |
        ButtonCore.shared.flagsChanged
    }
    let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 发送按钮事件通知
        NotificationCenter.default.post(name: buttonEventName, object: event)
        // 返回事件对象
        return Unmanaged.passUnretained(event)
    }
    // 按钮日志
    private var buttonEventLog: String = ""
    private let maxButtonLogLines = 50
    // 更新面板
    @objc private func updateButtonEventData(notification: NSNotification) {
        let event = notification.object as! CGEvent

        // 添加按钮标识符信息到描述中
        let logLine = "[\(event.formattedTimestamp())] \(event.displayName())"

        // 将新事件插入到日志开头，确保新事件在首行
        var logLines = buttonEventLog.isEmpty ? [] : buttonEventLog.components(separatedBy: "\n")
        logLines.insert(logLine, at: 0)
        
        // 管理日志行数，保持最新的 maxButtonLogLines 行（从开头保留）
        if logLines.count > maxButtonLogLines {
            logLines = Array(logLines.prefix(maxButtonLogLines))
        }
        
        buttonEventLog = logLines.joined(separator: "\n")
        
        // 更新按钮事件专用日志文本框
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            
            if let textView = strongSelf.buttonEventLogTextField {
                // 使用专用按钮事件文本框
                textView.string = strongSelf.buttonEventLog
                // 滚动到顶部以显示最新插入的事件（在首行）
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }
    }
    // 初始化
    func initButtonObserver() {
        // 监听内部事件
        NotificationCenter.default.addObserver(self, selector: #selector(updateButtonEventData), name: buttonEventName, object: nil)
        // 启动事件拦截
        // 启动按钮事件监控
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

    // MARK: - 按键事件处理

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
        buttonEventLog = ""
        buttonEventLogTextField?.string = ""
    }
}
