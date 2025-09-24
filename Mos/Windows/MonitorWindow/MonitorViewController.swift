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

    /// 将驼峰命名转换为用户友好的显示名称
    private func formatDisplayName(_ camelCaseName: String) -> String {
        // 插入空格在小写字母和大写字母之间
        var result = camelCaseName.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)

        // 处理数字和字母之间的空格
        result = result.replacingOccurrences(of: "([a-z])([0-9])", with: "$1 $2", options: .regularExpression)
        result = result.replacingOccurrences(of: "([0-9])([A-Z])", with: "$1 $2", options: .regularExpression)

        // 首字母大写
        return result.prefix(1).capitalized + result.dropFirst()
    }

    func setupShortcutMenu() {
        guard shortcutMenu != nil else {
            NSLog("[MonitorView] shortcutMenu 未连接，无法构建菜单")
            return
        }

        // 清空现有菜单项
        shortcutMenu.removeAllItems()

        NSLog("[MonitorView] 开始构建分级快捷键菜单...")

        // 添加 placeholder 项
        let placeholderItem = NSMenuItem(title: "Select an action", action: nil, keyEquivalent: "")
        placeholderItem.isEnabled = false
        shortcutMenu.addItem(placeholderItem)

        // 添加分割线
        shortcutMenu.addItem(NSMenuItem.separator())

        var totalShortcuts = 0

        // 按分类构建分级菜单
        for (categoryName, shortcuts) in SystemShortcut.shortcutsByCategory.sorted(by: { $0.key < $1.key }) {
            NSLog("[MonitorView] 创建分类子菜单: \(categoryName) (\(shortcuts.count) 个快捷键)")

            // 创建分类主菜单项
            let categoryMenuItem = NSMenuItem(title: categoryName, action: nil, keyEquivalent: "")

            // 创建子菜单
            let subMenu = NSMenu(title: categoryName)

            // 添加该分类下的所有快捷键到子菜单
            let sortedShortcuts = shortcuts.sorted { $0.key < $1.key }
            for (shortcutName, shortcut) in sortedShortcuts {
                let shortcutMenuItem = NSMenuItem(
                    title: "\(formatDisplayName(shortcutName)) - \(shortcut.displayName)",
                    action: #selector(onShortcutMenuItemSelected(_:)),
                    keyEquivalent: ""
                )
                shortcutMenuItem.target = self
                shortcutMenuItem.representedObject = shortcut
                shortcutMenuItem.toolTip = "测试快捷键: \(shortcut.displayName)"

                subMenu.addItem(shortcutMenuItem)
                totalShortcuts += 1
            }

            // 将子菜单关联到分类菜单项
            categoryMenuItem.submenu = subMenu

            // 将分类菜单项添加到主菜单
            shortcutMenu.addItem(categoryMenuItem)
        }

        // 设置默认选择 placeholder
        shortcutPopUpButton?.selectItem(at: 0)

        NSLog("[MonitorView] 分级快捷键菜单构建完成: \(SystemShortcut.shortcutsByCategory.count) 个分类，\(totalShortcuts) 个快捷键")
    }
    @objc func onShortcutMenuItemSelected(_ sender: NSMenuItem) {
        guard let shortcut = sender.representedObject as? SystemShortcut.Shortcut else {
            NSLog("[MonitorView] 无法获取快捷键信息")
            return
        }

        NSLog("[MonitorView] 菜单选择: \(sender.title)")

        NSLog("[MonitorView] 触发快捷键测试: \(shortcut.displayName) (keyCode: \(shortcut.keyCode), modifiers: \(shortcut.modifiers.rawValue))")

        do {
            // 构造键盘按下事件 (keyDown)
            guard let keyDownEvent = createKeyEvent(
                type: .keyDown,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers
            ) else {
                throw NSError(domain: "MonitorView", code: 1, userInfo: [NSLocalizedDescriptionKey: "keyDown 事件构造失败"])
            }

            NSLog("[MonitorView] ✓ keyDown 事件构造成功: \(keyDownEvent)")

            // 构造键盘抬起事件 (keyUp)
            guard let keyUpEvent = createKeyEvent(
                type: .keyUp,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers
            ) else {
                throw NSError(domain: "MonitorView", code: 2, userInfo: [NSLocalizedDescriptionKey: "keyUp 事件构造失败"])
            }

            NSLog("[MonitorView] ✓ keyUp 事件构造成功: \(keyUpEvent)")

            // 验证事件属性
            NSLog("[MonitorView] 事件详情:")
            NSLog("[MonitorView] - keyDown flags: \(keyDownEvent.flags.rawValue)")
            NSLog("[MonitorView] - keyUp flags: \(keyUpEvent.flags.rawValue)")
            NSLog("[MonitorView] - keyCode: \(keyDownEvent.getIntegerValueField(.keyboardEventKeycode))")

            NSLog("[MonitorView] ✓ 事件构造完成")

            // 显示倒计时并发送事件
            self.startCountdownAndPost(
                keyDownEvent: keyDownEvent,
                keyUpEvent: keyUpEvent,
                shortcut: shortcut
            )

        } catch {
            NSLog("[MonitorView] ✗ 事件构造失败: \(error.localizedDescription)")
        }
    }

    /// 创建键盘事件
    private func createKeyEvent(type: CGEventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> CGEvent? {
        // 创建基础键盘事件
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: type == .keyDown
        ) else {
            NSLog("[MonitorView] 无法创建基础键盘事件")
            return nil
        }

        // 设置修饰键
        var cgFlags: CGEventFlags = []

        if modifiers.contains(.command) {
            cgFlags.insert(.maskCommand)
        }
        if modifiers.contains(.shift) {
            cgFlags.insert(.maskShift)
        }
        if modifiers.contains(.option) {
            cgFlags.insert(.maskAlternate)
        }
        if modifiers.contains(.control) {
            cgFlags.insert(.maskControl)
        }
        if modifiers.contains(.function) {
            cgFlags.insert(.maskSecondaryFn)
        }

        event.flags = cgFlags

        // 设置时间戳
        event.timestamp = CGEventTimestamp(mach_absolute_time())

        return event
    }

    /// 倒计时并发送事件
    private func startCountdownAndPost(keyDownEvent: CGEvent, keyUpEvent: CGEvent, shortcut: SystemShortcut.Shortcut) {
        NSLog("[MonitorView] ⏱️ 1秒后发送 \(shortcut.displayName)")

        // 1秒延迟后发送事件
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            NSLog("[MonitorView] ⏱️ 延迟结束，开始发送事件")
            self?.postKeyboardEvents(keyDownEvent: keyDownEvent, keyUpEvent: keyUpEvent, shortcut: shortcut)
        }
    }

    /// 发送键盘事件到系统
    private func postKeyboardEvents(keyDownEvent: CGEvent, keyUpEvent: CGEvent, shortcut: SystemShortcut.Shortcut) {
        NSLog("[MonitorView] ⏰ [1秒后] 开始发送键盘事件: \(shortcut.displayName)")

        // 发送 keyDown 事件
        let keyDownLocation = CGEventTapLocation.cghidEventTap
        keyDownEvent.post(tap: keyDownLocation)
        NSLog("[MonitorView] ⬇️ keyDown 事件已发送到 eventTap (tap: \(keyDownLocation.rawValue))")

        // 短暂延迟，模拟真实按键时序
        usleep(10000) // 10ms

        // 发送 keyUp 事件
        let keyUpLocation = CGEventTapLocation.cghidEventTap
        keyUpEvent.post(tap: keyUpLocation)
        NSLog("[MonitorView] ⬆️ keyUp 事件已发送到 eventTap (tap: \(keyUpLocation.rawValue))")

        NSLog("[MonitorView] ✅ 快捷键 \(shortcut.displayName) 发送完成！")

        // 在界面显示完成信息并重置菜单
        DispatchQueue.main.async { [weak self] in
            self?.logEventCompletion(shortcut: shortcut)

            // 2秒后重置菜单到 placeholder
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.shortcutPopUpButton?.selectItem(at: 0)
                NSLog("[MonitorView] 菜单已重置到 placeholder")
            }
        }
    }

    /// 记录事件完成信息到界面
    private func logEventCompletion(shortcut: SystemShortcut.Shortcut) {
        // 在按钮事件日志中添加一条模拟记录
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let completionLine = "[\(timestamp)] 📤 已模拟触发: \(shortcut.displayName)"

        var logLines = buttonEventLog.isEmpty ? [] : buttonEventLog.components(separatedBy: "\n")
        logLines.insert(completionLine, at: 0)

        // 保持日志行数限制
        if logLines.count > maxButtonLogLines {
            logLines = Array(logLines.prefix(maxButtonLogLines))
        }

        buttonEventLog = logLines.joined(separator: "\n")

        if let textView = buttonEventLogTextField {
            textView.string = buttonEventLog
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
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
        buttonEventLog = ""
        buttonEventLogTextField?.string = ""
    }
}
