//
//  ViewController.swift
//  Mos
//  用于呈现滚动事件数据的View
//  Created by Cb on 2017/1/10.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Foundation
import Cocoa
import Charts

class ScrollMointorViewController: NSViewController {
    
    // 监听相关
    var eventTap:CFMachPort?
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let eventCallBack: CGEventTapCallBack = {
        (proxy, type, event, refcon) in
        // 发送ScrollWheelEventUpdate通知
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ScrollWheelEventMointorUpdate"), object: event)
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear() {
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
        
        // 开始截取事件 (ScrollWheelEventMointorUpdate)
        eventTap = ScrollCore.startCapture(event: mask, to: eventCallBack, at: .cgSessionEventTap, where: .tailAppendEventTap, for: .listenOnly)
        
        // 开始监听事件变更 (ScrollWheelEventMointorUpdate)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMointorData), name:NSNotification.Name(rawValue: "ScrollWheelEventMointorUpdate"), object: nil)
    }
    
    // 听到到event更新后, 这边更新Mointor
    @objc private func updateMointorData(notification: NSNotification) {
        let event = notification.object as! CGEvent
        
        // 更新图表数据
        let scrollY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        lineChart.data?.addEntry(ChartDataEntry(x: lineChartCount, y: scrollY), dataSetIndex: 0)
        lineChart.setVisibleXRange(minXRange: 1.0, maxXRange: 200.0)
        lineChart.moveViewToX(lineChartCount)
        lineChart.notifyDataSetChanged()
        lineChartCount += 1.0
        
        // 设置log数据
        scrollLogTextField.string = ScrollCore.getScrollLog(of: event)
        scrollDetailLogTextField.string = ScrollCore.getScrollDetailLog(of: event)
        processLogTextField.string = ScrollCore.getProcessLog(of: event)
        otherLogTextField.string = ScrollCore.getOtherLog(of: event)
    }
    
    override func viewWillDisappear() {
        // 停止截取事件 (ScrollWheelEventMointorUpdate)
        ScrollCore.stopCapture(tap: eventTap)
        // 移除监听事件变更 (ScrollWheelEventMointorUpdate)
        NotificationCenter.default.removeObserver(self)
    }

}

