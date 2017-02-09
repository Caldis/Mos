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

class ScrollMonitorViewController: NSViewController {
    
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
    var eventRecoderTap:CFMachPort?
    var scrollEventRecorder = [String]()
    var scrollEventRecorderOnRun = false
    var scrollEventRecorderOnReplay = false
    var scrollEventRecorderPlayOriginalEvent = true
    var scrollEventRecorderStartTime = NSDate()
    @IBOutlet weak var scrollEventRecoderTitle: NSTextField!
    @IBOutlet weak var scrollEventRecorderButton: NSButton!
    @IBOutlet weak var scrollEventRecoderPlayOriginEventCheckBox: NSButton!
    let eventRecoderCallBack: CGEventTapCallBack = {
        (proxy, type, event, refcon) in
        // 发送ScrollWheelEventUpdate通知
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ScrollWheelEventMonitorRecoder"), object: event)
        // 返回事件对象
        return Unmanaged.passRetained(event)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
            // 初始化载入log文件功能 (仅debug环境)
            let tapGesture = NSClickGestureRecognizer(target: self, action: #selector(scrollEventLoaderClick))
            scrollEventRecoderTitle.addGestureRecognizer(tapGesture)
        #else
            // 隐藏切换原始事件的CheckBox (Release环境)
            scrollEventRecoderPlayOriginEventCheckBox.isHidden = true
        #endif
        
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
        // 开始监听并输出滚动事件
        startMonitorScrollEvent()
    }
    
    
    // 开始监听
    func startMonitorScrollEvent() {
        // 开始截取事件 (ScrollWheelEventMonitorUpdate)
        eventTap = ScrollCore.startCapture(event: mask, to: eventCallBack, at: .cgSessionEventTap, where: .tailAppendEventTap, for: .listenOnly)
        // 开始监听事件变更 (ScrollWheelEventMonitorUpdate和ScrollWheelEventMonitorRecoder)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMonitorData), name:NSNotification.Name(rawValue: "ScrollWheelEventMonitorUpdate"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(recoderScrollEventData), name:NSNotification.Name(rawValue: "ScrollWheelEventMonitorRecoder"), object: nil)
    }
    // 停止监听
    func stopMonitorScrollEvent() {
        // 停止截取事件 (ScrollWheelEventMonitorUpdate)
        ScrollCore.stopCapture(tap: eventTap)
        // 移除监听事件变更 (ScrollWheelEventMonitorUpdate和ScrollWheelEventMonitorRecoder)
        NotificationCenter.default.removeObserver(self)
        // 重置记录状态
        stopRecordScrollEvent()
    }
    
    
    // 根据数据更新Monitor呈现
    @objc private func updateMonitorData(notification: NSNotification) {
        if scrollEventRecorderOnReplay {
            // 播放Log模式
            let data = notification.object as! String
            let eventData = data.components(separatedBy: ", ")
            // 更新图表数据
            let scrollY = Double(eventData[1])!
            lineChart.data?.addEntry(ChartDataEntry(x: lineChartCount, y: scrollY), dataSetIndex: 0)
            lineChart.setVisibleXRange(minXRange: 1.0, maxXRange: 200.0)
            lineChart.moveViewToX(lineChartCount)
            lineChart.notifyDataSetChanged()
            lineChartCount += 1.0
            // 设置log数据
            let scrollLog = eventData[3]
            let scrollDetailLog = eventData[4]
            let scrollProcessLog = eventData[5]
            scrollLogTextField.string = scrollLog
            scrollDetailLogTextField.string = scrollDetailLog
            processLogTextField.string = scrollProcessLog
        } else {
            // 正常监听模式
            let event = notification.object as! CGEvent
            // 更新图表数据
            let scrollY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            lineChart.data?.addEntry(ChartDataEntry(x: lineChartCount, y: scrollY), dataSetIndex: 0)
            lineChart.setVisibleXRange(minXRange: 1.0, maxXRange: 200.0)
            lineChart.moveViewToX(lineChartCount)
            lineChart.notifyDataSetChanged()
            lineChartCount += 1.0
            // 设置log数据
            let scrollLog = ScrollCore.getScrollLog(of: event)
            let scrollDetailLog = ScrollCore.getScrollDetailLog(of: event)
            let scrollProcessLog = ScrollCore.getProcessLog(of: event)
            let scrollOtherLog = ScrollCore.getOtherLog(of: event)
            scrollLogTextField.string = scrollLog
            scrollDetailLogTextField.string = scrollDetailLog
            processLogTextField.string = scrollProcessLog
            otherLogTextField.string = scrollOtherLog
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
            let scrollLog = ScrollCore.getScrollLog(of: event)
            let scrollDetailLog = ScrollCore.getScrollDetailLog(of: event)
            let scrollProcessLog = ScrollCore.getProcessLog(of: event)
            
            let timeInterval = String(NSDate().timeIntervalSince(scrollEventRecorderStartTime as Date))
            let log = [scrollData, scrollLog, scrollDetailLog, scrollProcessLog, timeInterval].joined(separator: ", ")
            scrollEventRecorder.append(log)
            scrollEventRecorder.append("logsTag")
        }
    }
    
    
    // 载入log文件 (仅Debug环境, 点击"记录"Title弹出)
    func scrollEventLoaderClick(_ sender: Any) {
        // 停止监听
        stopMonitorScrollEvent()
        // 切换到播放模式
        scrollEventRecorderOnReplay = true
        // 创建OpenPanel对象
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = NSURL.fileURL(withPath: "/dasktop", isDirectory: true)
        // 不可选择文件夹
        openPanel.canChooseDirectories = false
        // 能选择文件
        openPanel.canChooseFiles = true
        // 不允许复数选择
        openPanel.allowsMultipleSelection = false
        // 打开文件选择窗口
        openPanel.beginSheetModal(for: ScrollMonitorWindowController.scrollMonitorWindowRef, completionHandler: {
            result in
            if result == NSFileHandlingPanelOKButton && result == NSModalResponseOK {
                // 打开文件
                let applicationPath = openPanel.url!.path
                do {
                    // 读取文件
                    let stringData = try String(contentsOfFile: applicationPath, encoding: .utf8)
                    let arrayData = stringData.components(separatedBy: ", logsTag, ")
                    // 开始监听事件
                    if self.scrollEventRecorderPlayOriginalEvent {
                        NotificationCenter.default.addObserver(self, selector: #selector(self.updateMonitorData), name:NSNotification.Name(rawValue: "ScrollWheelEventMonitorUpdate"), object: nil)
                        for data in arrayData {
                            // 发送ScrollWheelEventUpdate通知
                            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ScrollWheelEventMonitorUpdate"), object: data)
                        }
                        NotificationCenter.default.removeObserver(self)
                        // 切换到监听模式
                        self.scrollEventRecorderOnReplay = false
                        // 重新开始监听
                        self.startMonitorScrollEvent()
                    } else {
                        for data in arrayData {
                            // 给SmoothScrolling处理
                            let eventData = data.components(separatedBy: ", ")
                            var scrollY = Int64(eventData[0])!
                            var scrollPtY = Double(eventData[1])!
                            var scrollFixY = Double(eventData[2])!
                            if scrollY != 0 {
                                if ScrollCore.option.reverse {
                                    scrollY = -scrollY
                                    scrollPtY = -scrollPtY
                                    scrollFixY = -scrollFixY
                                }
                                // 是否平滑滚动, 且窗口BundleId不包含在禁止翻转滚动列表内
                                if ScrollCore.option.smooth {
                                    // 如果输入值小于10, 则格式化为10
                                    let absY = abs(scrollPtY)
                                    if absY > 0.0 && absY < 10.0 {
                                        ScrollCore.updateScrollData(Y: scrollPtY<0.0 ? -10.0 : 10.0, X: 0.0)
                                    } else {
                                        ScrollCore.updateScrollData(Y: scrollPtY, X: 0.0)
                                    }
                                    // 启动一下事件
                                    ScrollCore.activeScrollEventPoster()
                                }
                            }
                        }
                        // 切换到监听模式
                        self.scrollEventRecorderOnReplay = false
                        // 重新开始监听
                        self.startMonitorScrollEvent()
                    }
                } catch {
                    print(error)
                }
            }
        })
    }
    // 点击录制滚动事件
    @IBAction func scrollEventRecorderButtonClick(_ sender: NSButton) {
        // 点击切换状态
        scrollEventRecorderOnRun = !scrollEventRecorderOnRun
        if scrollEventRecorderOnRun {
            // 开始录制
            startRecordScrollEvent()
        } else {
            // 停止录制
            stopRecordScrollEvent()
            // 保存到文件
            saveRecordScrollEvent()
        }
    }
    // 开始录制
    func startRecordScrollEvent() {
        scrollEventRecorder = [String]()
        scrollEventRecorderButton.image = #imageLiteral(resourceName: "ScrollMonitorStopRecorder")
        scrollEventRecorderStartTime = NSDate()
        // 开始截取事件 (ScrollWheelEventMonitorUpdate)
        eventRecoderTap = ScrollCore.startCapture(event: mask, to: eventRecoderCallBack, at: .cghidEventTap, where: .headInsertEventTap, for: .listenOnly)
        
    }
    // 停止录制
    func stopRecordScrollEvent() {
        scrollEventRecorderButton.image = #imageLiteral(resourceName: "ScrollMonitorStartRecorder")
        scrollEventRecorderOnRun = false
        // 停止截取事件 (ScrollWheelEventMonitorUpdate)
        if eventRecoderTap !== nil {
            ScrollCore.stopCapture(tap: eventRecoderTap)
        }
    }
    // 保存录制结果
    func saveRecordScrollEvent() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "scrollEventLog.log"
        savePanel.directoryURL = NSURL.fileURL(withPath: "/desktop", isDirectory: true)
        savePanel.beginSheetModal(for: ScrollMonitorWindowController.scrollMonitorWindowRef, completionHandler: {
            result in
            if result == NSFileHandlingPanelOKButton && result == NSModalResponseOK {
                let selectedUrl = savePanel.url!
                let selectedPath = selectedUrl.path
                FileManager().createFile(atPath: selectedPath, contents: nil, attributes: nil)
                let logs = self.scrollEventRecorder.dropLast().joined(separator: ", ")
                do {
                    try logs.write(to: selectedUrl, atomically: false, encoding: String.Encoding.utf8)
                }
                catch {
                    print("Write file ERR !")
                }
            }
        })
    }
    // 点击切换播放原始log还是平滑后的log
    @IBAction func scrollEventRecoderPlayOriginEventCheckBoxOnToggle(_ sender: NSButton) {
        scrollEventRecorderPlayOriginalEvent = sender.state==1 ? true : false
    }
    
    
    override func viewWillDisappear() {
        // 停止监听
        stopMonitorScrollEvent()
    }
    
}

class ScrollMonitorHelpViewController: NSViewController {
    
    @IBOutlet weak var issueUrl: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let tapGesture = NSClickGestureRecognizer(target: self, action: #selector(issueUrlClick))
        issueUrl.addGestureRecognizer(tapGesture)
    }
    
    func issueUrlClick() {
        NSWorkspace.shared().open(URL(string: "https://github.com/Caldis/Mos/issues")!)
    }
    
}
