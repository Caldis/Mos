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
        // 定义颜色
        let green = NSUIColor(red: 96.0/255.0, green: 198.0/255.0, blue: 85.0/255.0, alpha: 1.0)
        let yellow = NSUIColor(red: 246.0/255.0, green: 191.0/255.0, blue: 79.0/255.0, alpha: 1.0)
        // 设置代理
        lineChart.delegate = self
        // 初始化图表数据
        lineChartCount = 0.0
        // 设置数据集
        let verticalData = LineChartDataSet(values: [ChartDataEntry(x: 0.0, y: 0.0)], label: "Vertical")
        verticalData.valueTextColor = NSUIColor.white
        verticalData.colors = [green]
        verticalData.circleRadius = 1.5
        verticalData.circleColors = [green]
        let horizontalData = LineChartDataSet(values: [ChartDataEntry(x: 0.0, y: 0.0)], label: "Horizontal")
        horizontalData.valueTextColor = NSUIColor.white
        horizontalData.colors = [yellow]
        horizontalData.circleRadius = 1.5
        horizontalData.circleColors = [yellow]
        lineChart.data = LineChartData(dataSets: [verticalData, horizontalData])
        // 设置图表样式
        lineChart.noDataTextColor = NSUIColor.white
        lineChart.chartDescription?.text = ""
        lineChart.legend.textColor = NSUIColor.white
        lineChart.xAxis.labelTextColor = NSUIColor.white
        lineChart.leftAxis.labelTextColor = NSUIColor.white
        lineChart.rightAxis.labelTextColor = NSUIColor.white
        lineChart.drawBordersEnabled = true
        lineChart.borderColor = NSUIColor.gray
    }
    // 初始化监听
    func initObserver() {
        // 移除原有
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMonitorData), name:NSNotification.Name(rawValue: "ScrollEvent"), object: nil)
        // 开始截取事件
        eventTap = Interception.start(event: mask, to: eventCallBack, at: .cgAnnotatedSessionEventTap, where: .tailAppendEventTap, for: .listenOnly)
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
        if let data = lineChart.data {
            data.addEntry(ChartDataEntry(x: lineChartCount, y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)), dataSetIndex: 0)
            data.addEntry(ChartDataEntry(x: lineChartCount, y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)), dataSetIndex: 1)
            lineChart.setVisibleXRange(minXRange: 1.0, maxXRange: 100.0)
            lineChart.moveViewToX(lineChartCount)
            lineChart.notifyDataSetChanged()
            lineChartCount += 1.0
        }
        // 更新Log区域
        scrollLogTextField.string = Logger.getScrollLog(form: event)
        scrollDetailLogTextField.string = Logger.getScrollDetailLog(form: event)
        processLogTextField.string = Logger.getProcessLog(form: event)
        otherLogTextField.string = Logger.getOtherLog(form: event)
    }
    
    // 刷新图表
    @IBAction func refreshChart(_ sender: Any) {
        initCharts()
    }
}
