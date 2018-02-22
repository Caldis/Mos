//
//  ScrollMonitorViewController.swift
//  Mos
//  滚动监控界面
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Foundation
import Cocoa
import Charts

class ScrollMonitorViewController: NSViewController, ChartViewDelegate {
    
    // 监听相关
    var eventTap:CFMachPort?
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let eventCallBack: CGEventTapCallBack = {
        (proxy, type, event, refcon) in
        // 发送ScrollWheelEventUpdate通知
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ScrollWheelEventMonitorUpdate"), object: event)
        // 返回事件对象
        return Unmanaged.passRetained(event)
    }
    
    // 图表相关
    var lineChartCount = 0.0
    @IBOutlet weak var lineChart: LineChartView!
    
    // 文字Log区域相关
    @IBOutlet var scrollLogTextField: NSTextView!
    @IBOutlet var scrollDetailLogTextField: NSTextView!
    @IBOutlet var processLogTextField: NSTextView!
    @IBOutlet var otherLogTextField: NSTextView!
    
    // Recorder相关
    var scrollEventLoadedData:[String]?
    var eventRecoderTap:CFMachPort?
    var scrollEventRecorder = [String]()
    var scrollEventRecorderOnRun = false
    var scrollEventRecorderOnReplay = false
    var scrollEventRecorderPlayOriginalEvent = true
    var scrollEventRecorderStartTime = NSDate()
    let eventRecoderCallBack: CGEventTapCallBack = {
        (proxy, type, event, refcon) in
        // 发送ScrollWheelEventUpdate通知
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ScrollWheelEventMonitorRecoder"), object: event)
        // 返回事件对象
        return Unmanaged.passRetained(event)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear() {
        // 设置代理
        lineChart.delegate = self
        // 初始化图表数据
        lineChartCount = 0.0
        let dataSet = LineChartDataSet(values: [ChartDataEntry(x: 0.0, y: 0.0)], label: "ScrollData")
        lineChart.data = LineChartData(dataSets: [dataSet])
        lineChart.chartDescription?.text = ""
        lineChart.legend.textColor = NSUIColor.white
        lineChart.xAxis.labelTextColor = NSUIColor.white
        lineChart.leftAxis.labelTextColor = NSUIColor.white
        lineChart.rightAxis.labelTextColor = NSUIColor.white
        // 设置图表样式
        dataSet.valueTextColor = NSUIColor.white
        dataSet.colors = [NSUIColor.white]
        dataSet.circleRadius = 1.5
        dataSet.circleColors = [NSUIColor.white]
        // 开始监听并输出滚动事件
        startMonitorScrollEvent()
    }
    
    
    // 点击chart对应位置时呈现对应数据
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        if scrollEventLoadedData != nil {
            let eventData = scrollEventLoadedData![Int(highlight.x)].components(separatedBy: ", ")
            updateLogView(eventData[3], eventData[4], eventData[5], nil)
        }
    }
    
    
    // 开始监听
    func startMonitorScrollEvent() {
        // 开始截取事件 (ScrollWheelEventMonitorUpdate)
        eventTap = ScrollCore.shared.startCapture(event: mask, to: eventCallBack, at: .cgSessionEventTap, where: .tailAppendEventTap, for: .listenOnly)
        // 开始监听事件变更 (ScrollWheelEventMonitorUpdate和ScrollWheelEventMonitorRecoder)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMonitorData), name:NSNotification.Name(rawValue: "ScrollWheelEventMonitorUpdate"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(recoderScrollEventData), name:NSNotification.Name(rawValue: "ScrollWheelEventMonitorRecoder"), object: nil)
    }
    // 停止监听
    func stopMonitorScrollEvent() {
        // 停止截取事件 (ScrollWheelEventMonitorUpdate)
        ScrollCore.shared.stopCapture(tap: eventTap)
        // 移除监听事件变更 (ScrollWheelEventMonitorUpdate和ScrollWheelEventMonitorRecoder)
        NotificationCenter.default.removeObserver(self)
    }
    
    
    // 根据数据更新Monitor呈现
    @objc private func updateMonitorData(notification: NSNotification) {
        if scrollEventRecorderOnReplay {
            // 播放Log模式
            let data = notification.object as! String
            let eventData = data.components(separatedBy: ", ")
            // 更新图表数据
            updateChartView(x: lineChartCount, y: Double(eventData[1])!)
            // 设置log数据
            updateLogView(eventData[3], eventData[4], eventData[5], nil)
        } else {
            // 正常监听模式
            let event = notification.object as! CGEvent
            // 更新图表数据
            updateChartView(x: lineChartCount, y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            // 设置log数据
            updateLogView(Logger.getScrollLog(of: event), Logger.getScrollDetailLog(of: event), Logger.getProcessLog(of: event), Logger.getOtherLog(of: event))
        }
    }
    @objc private func recoderScrollEventData(notification: NSNotification) {
        let event = notification.object as! CGEvent
        // 如果正在录制, 则将事件怼到scrollEventRecorder内
        if scrollEventRecorderOnRun {
            // 滚动数据
            let scrollY = String(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            let scrollPtY = String(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            let scrollFixY = String(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
            let scrollData = [scrollY, scrollPtY, scrollFixY].joined(separator: ", ")
            // Log数据
            let scrollLog = Logger.getScrollLog(of: event)
            let scrollDetailLog = Logger.getScrollDetailLog(of: event)
            let scrollProcessLog = Logger.getProcessLog(of: event)
            
            let timeInterval = String(NSDate().timeIntervalSince(scrollEventRecorderStartTime as Date))
            let log = [scrollData, scrollLog, scrollDetailLog, scrollProcessLog, timeInterval].joined(separator: ", ")
            scrollEventRecorder.append(log)
            scrollEventRecorder.append("logsTag")
        }
    }
    // 更新Chart区域
    func updateChartView(x: Double, y: Double) {
        lineChart.data?.addEntry(ChartDataEntry(x: x, y: y), dataSetIndex: 0)
        lineChart.setVisibleXRange(minXRange: 1.0, maxXRange: 200.0)
        lineChart.moveViewToX(x)
        lineChart.notifyDataSetChanged()
        lineChartCount += 1.0
    }
    // 更新Log区域
    func updateLogView(_ scrollLog: String?, _ scrollDetailLog: String?, _ scrollProcessLog: String?, _ scrollOtherLog: String?) {
        if scrollLog != nil {
            scrollLogTextField.string = scrollLog!
        } else {
            scrollLogTextField.string = "No Data"
        }
        if scrollDetailLog != nil {
            scrollDetailLogTextField.string = scrollDetailLog!
        } else {
            scrollDetailLogTextField.string = "No Data"
        }
        if scrollProcessLog != nil {
            processLogTextField.string = scrollProcessLog!
        } else {
            processLogTextField.string = "No Data"
        }
        if scrollOtherLog != nil {
            otherLogTextField.string = scrollOtherLog!
        } else {
            otherLogTextField.string = "No Data"
        }
    }
    
    override func viewWillDisappear() {
        // 停止监听
        stopMonitorScrollEvent()
    }
    
}
