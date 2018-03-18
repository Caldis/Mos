//
//  MonitorViewController.swift
//  Mos
//  滚动监控界面
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa
import Charts

class MonitorViewController: NSViewController, ChartViewDelegate {
    
    // 图表相关
    var lineChartCount = 0.0
    @IBOutlet weak var lineChart: LineChartView!
    
    // 文字Log区域相关
    @IBOutlet var scrollLogTextField: NSTextView!
    @IBOutlet var scrollDetailLogTextField: NSTextView!
    @IBOutlet var processLogTextField: NSTextView!
    @IBOutlet var otherLogTextField: NSTextView!
    
    // 监听相关
    var eventTap:CFMachPort?
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let eventCallBack: CGEventTapCallBack = {
        (proxy, type, event, refcon) in
        // 发送 ScrollWheelEventUpdate 通知
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ScrollEvent"), object: event)
        // 返回事件对象
        return Unmanaged.passRetained(event)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    override func viewWillAppear() {
        // 初始化图表
        initCharts()
        // 初始化监听
        initObserver()
    }
    override func viewWillDisappear() {
        uninitObserver()
    }
    
    // 图表
    func initCharts() {
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
    }
    // 初始化监听
    func initObserver() {
        // 移除原有
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMonitorData), name:NSNotification.Name(rawValue: "ScrollEvent"), object: nil)
        // 开始截取事件
        eventTap = Interception.start(event: mask, to: eventCallBack, at: .cgSessionEventTap, where: .tailAppendEventTap, for: .listenOnly)
    }
    func uninitObserver() {
        // 停止截取
        Interception.stop(tap: eventTap)
        // 停止监听
        NotificationCenter.default.removeObserver(self)
    }
    
    // 根据数据更新 Monitor 呈现
    @objc private func updateMonitorData(notification: NSNotification) {
        let event = notification.object as! CGEvent
        // 更新图表数据
        updateChartView(x: lineChartCount, y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        // 设置log数据
        updateLogView(Logger.getScrollLog(form: event), Logger.getScrollDetailLog(form: event), Logger.getProcessLog(form: event), Logger.getOtherLog(form: event))
    }
    // 更新Chart区域
    func updateChartView(x: Double, y: Double) {
        lineChart.data?.addEntry(ChartDataEntry(x: x, y: y), dataSetIndex: 0)
        lineChart.setVisibleXRange(minXRange: 1.0, maxXRange: 100.0)
        lineChart.moveViewToX(x)
        lineChart.notifyDataSetChanged()
        lineChartCount += 1.0
    }
    // 更新Log区域
    func updateLogView(_ scrollLog: String?, _ scrollDetailLog: String?, _ scrollProcessLog: String?, _ scrollOtherLog: String?) {
        scrollLogTextField.string = scrollLog!
        scrollDetailLogTextField.string = scrollDetailLog!
        processLogTextField.string = scrollProcessLog!
        otherLogTextField.string = scrollOtherLog!
    }
    
}
