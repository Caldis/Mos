//
//  PreferencesButtonsViewController.swift
//  Mos
//  按钮绑定配置界面
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesButtonsViewController: NSViewController {

    // MARK: - Recorder
    private var recorder = KeyRecorder()

    // MARK: - Data
    private var buttonBindings: [ButtonBinding] = []
    private var currentOpenTargetPopover: OpenTargetConfigPopover?

    // MARK: - UI Elements
    // 表格
    @IBOutlet weak var tableHead: NSVisualEffectView!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableEmpty: NSView!
    @IBOutlet weak var tableFoot: NSView!
    // 按钮
    @IBOutlet weak var createButton: PrimaryButton!
    @IBOutlet weak var addButton: NSButton!
    @IBOutlet weak var delButton: NSButton!
    // Logi HID 活动指示器 (底部右下角 spinner, 仅与 UI 呈现相关, 不参与业务逻辑判定)
    @IBOutlet weak var activityIndicator: NSProgressIndicator!

    // MARK: - Activity Indicator State (UI-only)
    /// 最短可见时长 (秒): 防止快速结束的查询让 spinner 只闪一下造成困惑.
    private static let activityIndicatorMinVisibleDuration: TimeInterval = 0.5
    /// popover 可见时的轮询间隔 (秒); 只在 popover show 期间开启, 关闭即停.
    private static let activityPopoverPollInterval: TimeInterval = 0.25
    /// 热区 overlay 尺寸 (pt). spinner 本身只有 12pt, 直接作为 hover 热区太小;
    /// 和冲突图标 ButtonTableCellView.conflictHitSize=28 取齐, hover 体验一致.
    private static let activityHitSize: CGFloat = 28
    /// 透明热区容器, 覆盖在 spinner 中心位置, 承担 tracking area — spinner 本身不做事件.
    private var activityHitOverlay: NSView?
    /// spinner 开始动画的时间戳 (主线程读写).
    private var activityIndicatorShownAt: Date?
    /// busy 翻回 false 但未满最短时长时的延迟停止任务; 若中途再次 busy=true 则取消.
    private var pendingActivityStopWorkItem: DispatchWorkItem?
    /// hover popover 与其 content VC (懒创建, 仅在首次 hover 时产生).
    /// content VC 复用 AdaptivePopover, 自动算尺寸 — 本 VC 只管文案更新.
    private var activityPopover: NSPopover?
    private var activityPopoverContent: ActivityPopoverViewController?
    /// popover 展示期间的轮询 timer; 关闭时必须 invalidate.
    private var activityPopoverPollTimer: Timer?
    /// spinner 上的 tracking area, bounds 变化时需重建.
    private var activityTrackingArea: NSTrackingArea?

    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置代理
        recorder.delegate = self
        tableView.delegate = self
        tableView.dataSource = self
        // 读取设置
        loadOptionsToView()
        // 指示器: tooltip + 订阅 Manager 活动状态变化通知
        setupActivityIndicator()
    }

    override func viewWillAppear() {
        // 检查表格数据
        toggleNoDataHint()
        // 设置录制按钮回调
        setupRecordButtonCallback()
        // 触发一次冲突状态刷新 (30s 内最多跑一次,异步)
        LogiCenter.shared.refreshReportingStates()
        // 面板出现时同步一次当前 busy 状态, 避免错过此前发出的通知
        syncActivityIndicatorWithManager()
    }

    override func viewWillDisappear() {
        // 切 tab / 关窗时彻底收敛 popover + 轮询, 避免后台空转.
        closeActivityPopoverIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pendingActivityStopWorkItem?.cancel()
        activityPopoverPollTimer?.invalidate()
        activityPopover?.performClose(nil)
    }

    // 添加
    @IBAction func addItemClick(_ sender: NSButton) {
        recorder.startRecording(from: sender)
    }
    // 删除
    @IBAction func removeItemClick(_ sender: NSButton) {
        // 确保选择了行
        guard tableView.selectedRow != -1 else { return }
        // 统一通过 removeButtonBinding 处理删除逻辑
        let binding = buttonBindings[tableView.selectedRow]
        removeButtonBinding(id: binding.id)
        // 更新删除按钮状态
        updateDelButtonState()
    }
}

/**
 * 数据持久化
 **/
extension PreferencesButtonsViewController {
    // 从 Options 加载到界面
    func loadOptionsToView() {
        buttonBindings = Options.shared.buttons.binding
        tableView.reloadData()
        toggleNoDataHint()
    }

    private func collectButtonBindingCodes() -> Set<UInt16> {
        var codes = Set<UInt16>()
        for binding in ButtonUtils.shared.getButtonBindings() where binding.isEnabled && binding.triggerEvent.type == .mouse {
            codes.insert(binding.triggerEvent.code)
        }
        return codes
    }

    // 保存界面到 Options, 并同步 divert 状态
    func syncViewWithOptions() {
        Options.shared.buttons.binding = buttonBindings
        ButtonUtils.shared.invalidateCache()
        // 绑定变更后同步 HID++ divert: 只 divert 有绑定的按键
        let codes = collectButtonBindingCodes()
        LogiCenter.shared.setUsage(source: .buttonBinding, codes: codes)
    }

    // 更新删除按钮状态
    func updateDelButtonState() {
        delButton.isEnabled = tableView.selectedRow != -1
    }

    // 设置录制按钮回调
    private func setupRecordButtonCallback() {
        createButton.onMouseDown = { [weak self] target in
            self?.recorder.startRecording(from: target)
        }
    }
    
    private func addRecordedEvent(_ event: InputEvent, isDuplicate: Bool) {
        let recordedEvent = normalizedRecordedEventForButtonBinding(from: event)
        let normalizedDuplicate = buttonBindings.contains(where: { $0.triggerEvent == recordedEvent })

        if normalizedDuplicate {
            if let existing = buttonBindings.first(where: { $0.triggerEvent == recordedEvent }) {
                highlightExistingRow(with: existing.id)
            }
            return
        }

        let binding = ButtonBinding(triggerEvent: recordedEvent, systemShortcutName: "", isEnabled: false)
        buttonBindings.append(binding)
        tableView.reloadData()
        toggleNoDataHint()
        notifyBLEHIDPPUnstableIfNeeded(for: recordedEvent)
        syncViewWithOptions()
    }

    private func notifyBLEHIDPPUnstableIfNeeded(for event: RecordedEvent) {
        guard event.type == .mouse,
              LogiCenter.shared.isLogiCode(event.code) else { return }
        let status = ButtonCapturePresentationStatus.from(
            LogiCenter.shared.buttonCaptureDiagnosis(forMosCode: event.code)
        )
        guard status == .bleHIDPPUnstable else { return }
        LogiCenter.shared.showBLEHIDPPUnstableToast(forMosCode: event.code)
    }

    // 高亮已存在的行 (用于重复录制的视觉反馈)
    private func highlightExistingRow(with id: UUID) {
        guard let row = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        tableView.deselectAll(nil)
        tableView.scrollRowToVisible(row)
        if let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ButtonTableCellView {
            cellView.highlight()
        }
    }

    // 删除按钮绑定
    func removeButtonBinding(id: UUID) {
        buttonBindings.removeAll(where: { $0.id == id })
        tableView.reloadData()
        toggleNoDataHint()
        syncViewWithOptions()
    }

    /// 更新按钮绑定
    /// - Parameters:
    ///   - id: 绑定记录的唯一标识
    ///   - shortcut: 系统快捷键对象,nil 表示清除绑定
    func updateButtonBinding(id: UUID, with shortcut: SystemShortcut.Shortcut?) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }

        let oldBinding = buttonBindings[index]

        let updatedBinding: ButtonBinding
        if let shortcut = shortcut {
            // 绑定快捷键:直接使用快捷键的 identifier
            updatedBinding = ButtonBinding(
                id: oldBinding.id,
                triggerEvent: oldBinding.triggerEvent,
                systemShortcutName: shortcut.identifier,
                isEnabled: true
            )
        } else {
            // 清除绑定:保持触发事件,清空快捷键名称并禁用
            updatedBinding = ButtonBinding(
                id: oldBinding.id,
                triggerEvent: oldBinding.triggerEvent,
                systemShortcutName: "",
                isEnabled: false
            )
        }

        buttonBindings[index] = updatedBinding
        syncViewWithOptions()
    }

    /// 更新按钮绑定 (自定义快捷键)
    func updateButtonBinding(id: UUID, withCustomName name: String) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        let old = buttonBindings[index]
        buttonBindings[index] = ButtonBinding(
            id: old.id,
            triggerEvent: old.triggerEvent,
            systemShortcutName: name,
            isEnabled: true,
            createdAt: old.createdAt
        )
        syncViewWithOptions()
    }

    /// 更新按钮绑定 ("打开应用" 动作)
    func updateButtonBinding(id: UUID, withOpenTarget payload: OpenTargetPayload) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        let old = buttonBindings[index]
        buttonBindings[index] = ButtonBinding(
            id: old.id,
            triggerEvent: old.triggerEvent,
            openTarget: payload,
            isEnabled: true,
            createdAt: old.createdAt
        )
        syncViewWithOptions()
        tableView.reloadData()
    }

    func replaceButtonBinding(_ binding: ButtonBinding) {
        guard buttonBindings.contains(where: { $0.id == binding.id }) else { return }
        buttonBindings = ButtonBindingReplacement.replacing(binding, in: buttonBindings)
        tableView.reloadData()
        toggleNoDataHint()
        syncViewWithOptions()
    }

    private func presentOpenTargetPopover(forBindingID id: UUID) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        guard let row = tableView.row(forBinding: id, in: buttonBindings) else { return }
        guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ButtonTableCellView else { return }

        let existing = buttonBindings[index].openTarget

        let popover = OpenTargetConfigPopover()
        currentOpenTargetPopover = popover
        popover.onCommit = { [weak self] payload in
            self?.updateButtonBinding(id: id, withOpenTarget: payload)
            self?.currentOpenTargetPopover = nil
        }
        popover.onCancel = { [weak self] in
            self?.currentOpenTargetPopover = nil
        }
        popover.show(at: cell.actionPopUpButton, existing: existing)
    }
}

/**
 * 表格区域渲染及操作
 **/
extension PreferencesButtonsViewController: NSTableViewDelegate, NSTableViewDataSource {
    // 无数据
    func toggleNoDataHint() {
        let hasData = buttonBindings.count != 0
        updateViewVisibility(view: createButton, visible: !hasData)
        updateViewVisibility(view: tableEmpty, visible: !hasData)
        updateViewVisibility(view: tableHead, visible: hasData)
        updateViewVisibility(view: tableFoot, visible: hasData)
    }
    private func updateViewVisibility(view: NSView, visible: Bool) {
        view.isHidden = !visible
        view.animator().alphaValue = visible ? 1 : 0
    }
    
    // 表格数据源
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumnIdentifier = tableColumn?.identifier else { return nil }

        // 创建 Cell
        if let cell = tableView.makeView(withIdentifier: tableColumnIdentifier, owner: self) as? ButtonTableCellView {
            let binding = buttonBindings[row]

            cell.configure(
                with: binding,
                onShortcutSelected: { [weak self] shortcut in
                    self?.updateButtonBinding(id: binding.id, with: shortcut)
                },
                onCustomShortcutRecorded: { [weak self] customName in
                    self?.updateButtonBinding(id: binding.id, withCustomName: customName)
                },
                onOpenTargetSelectionRequested: { [weak self] in
                    self?.presentOpenTargetPopover(forBindingID: binding.id)
                },
                onDeleteRequested: { [weak self] in
                    self?.removeButtonBinding(id: binding.id)
                },
                onBindingUpdated: { [weak self] updated in
                    self?.replaceButtonBinding(updated)
                }
            )
            return cell
        }

        return nil
    }
    
    // 行高
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 44
    }
    
    // 行数
    func numberOfRows(in tableView: NSTableView) -> Int {
        return buttonBindings.count
    }

    // 选择变化
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDelButtonState()
    }

    // Type Selection 支持
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard row < buttonBindings.count else { return nil }
        let components = buttonBindings[row].triggerEvent.displayComponents
        // 去掉第一项（修饰键），只保留实际按键用于匹配
        let keyOnly = components.count > 1 ? Array(components.dropFirst()) : components
        return keyOnly.joined(separator: " ")
    }
}

// MARK: - Logi Activity Indicator
extension PreferencesButtonsViewController {
    /// 一次性配置: tooltip + tracking area + 订阅 Manager 的活动状态通知.
    /// 通知回调 (main-thread post) 直接驱动 NSProgressIndicator, 不做任何 HID 查询,
    /// 保证视图层与检测逻辑彻底解耦.
    fileprivate func setupActivityIndicator() {
        // 不设 toolTip: 自定义 NSPopover 信息更丰富 (phase / 设备 / 进度),
        // 两者并存会在 hover 时同时弹出系统黄色 tooltip + popover, 视觉冲突.
        activityIndicator.isDisplayedWhenStopped = false
        // 程序化加一个 28pt 透明热区 overlay 覆盖 spinner 中心 (对齐 ButtonTableCellView 的 conflictHitSize=28).
        // spinner 改 mini (12pt) 后热区需独立外扩, 否则 hover 很难命中.
        setupActivityHitOverlay()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleActivityStateChanged(_:)),
            name: LogiCenter.activityChanged,
            object: nil
        )
    }

    /// 在 spinner 中心覆盖一个不绘制内容的 NSView 做热区载体, tracking area 挂它上面.
    /// overlay 一次性加入 root view, 约束跟随 spinner center, 生命周期与 VC 一致, 无需 layout 回调重建.
    private func setupActivityHitOverlay() {
        let overlay = NSView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: activityIndicator.centerXAnchor),
            overlay.centerYAnchor.constraint(equalTo: activityIndicator.centerYAnchor),
            overlay.widthAnchor.constraint(equalToConstant: Self.activityHitSize),
            overlay.heightAnchor.constraint(equalToConstant: Self.activityHitSize)
        ])
        activityHitOverlay = overlay

        let area = NSTrackingArea(
            rect: .zero,  // .inVisibleRect 模式下忽略 rect, 自动用 overlay 可见区域
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        overlay.addTrackingArea(area)
        activityTrackingArea = area
    }

    @objc private func handleActivityStateChanged(_ note: Notification) {
        syncActivityIndicatorWithManager()
    }

    /// 把当前 Manager.isBusy 映射到 spinner 的可见性, 带 500ms 最短显示;
    /// 同时把 busy=false 同步到 popover (若正在展示, 立即关闭).
    fileprivate func syncActivityIndicatorWithManager() {
        let busy = LogiCenter.shared.isBusy
        if busy {
            pendingActivityStopWorkItem?.cancel()
            pendingActivityStopWorkItem = nil
            if activityIndicatorShownAt == nil {
                activityIndicatorShownAt = Date()
                activityIndicator.startAnimation(nil)
            }
        } else {
            // 用户要求: loading 结束时 popover 同步回收 (即使还在 hover).
            closeActivityPopoverIfNeeded()
            scheduleActivityIndicatorStop()
        }
    }

    private func scheduleActivityIndicatorStop() {
        guard let shownAt = activityIndicatorShownAt else { return }
        let elapsed = Date().timeIntervalSince(shownAt)
        let minDuration = Self.activityIndicatorMinVisibleDuration
        if elapsed >= minDuration {
            stopActivityIndicatorNow()
            return
        }
        pendingActivityStopWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stopActivityIndicatorNow()
        }
        pendingActivityStopWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (minDuration - elapsed), execute: work)
    }

    private func stopActivityIndicatorNow() {
        pendingActivityStopWorkItem = nil
        activityIndicatorShownAt = nil
        activityIndicator.stopAnimation(nil)
    }

    // MARK: - Hover Popover

    override func mouseEntered(with event: NSEvent) {
        // 只对 spinner 的 tracking area 响应; 其他未来可能加的 tracking 不干扰.
        guard event.trackingArea === activityTrackingArea else {
            super.mouseEntered(with: event)
            return
        }
        // 不忙时不弹 (即便 tracking area 理论上已 hidden 了也兜一层)
        guard LogiCenter.shared.isBusy else { return }
        showActivityPopover()
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === activityTrackingArea else {
            super.mouseExited(with: event)
            return
        }
        closeActivityPopoverIfNeeded()
    }

    /// 参考 `ButtonTableCellView.showConflictPopover` 的极简模式:
    /// - 每次 hover 进入新建一个 NSPopover, 不复用;
    /// - 用 `conflictPopover == nil` 作为互斥守卫;
    /// - hide 时同步 `close() + popover = nil`, 不依赖 delegate 回调.
    /// 这样避免 `performClose` 关闭动画或 `.transient` 自动行为引入的中间态,
    /// 用户 mouseExit 后立即重入时 guard 放行, popover 能即刻出现.
    private func showActivityPopover() {
        guard activityPopover == nil else { return }
        let popover = makeActivityPopover()
        activityPopover = popover
        refreshActivityPopoverContent()
        popover.show(relativeTo: activityIndicator.bounds,
                     of: activityIndicator,
                     preferredEdge: .maxY)
        // 打开轮询 (main RunLoop .common, menu tracking 期间也保持节奏);
        // 关闭由 closeActivityPopoverIfNeeded 统一收口, 不依赖 popoverDidClose.
        let timer = Timer(timeInterval: Self.activityPopoverPollInterval, repeats: true) { [weak self] _ in
            self?.refreshActivityPopoverContent()
        }
        RunLoop.main.add(timer, forMode: .common)
        activityPopoverPollTimer = timer
    }

    private func closeActivityPopoverIfNeeded() {
        activityPopoverPollTimer?.invalidate()
        activityPopoverPollTimer = nil
        activityPopover?.close()
        activityPopover = nil
        activityPopoverContent = nil
    }

    /// 从 Manager 拉快照并渲染. 没有活跃 session 时展示兜底文案 (过渡态).
    /// 尺寸自适应完全由 AdaptivePopover (content VC 的父类) 负责, 本方法只推文案.
    private func refreshActivityPopoverContent() {
        guard let content = activityPopoverContent else { return }
        let summary = LogiCenter.shared.currentActivitySummary
        content.setMessage(Self.formatActivitySummary(summary))
    }

    /// 聚合多个 session 成一行或多行简短文字.
    /// 单设备: "正在刷新冲突状态 · MX Master 3S · 5/12"
    /// 多设备: 每个设备一行
    private static func formatActivitySummary(_ summary: [SessionActivityStatus]) -> String {
        guard !summary.isEmpty else {
            return NSLocalizedString("button_activity_popover_fallback",
                                     comment: "Shown when busy state ends while popover is closing")
        }
        return summary.map { status -> String in
            let phaseLabel: String
            switch status.phase {
            case .discovery:
                phaseLabel = NSLocalizedString("button_activity_phase_discovery",
                                               comment: "Phase: initial handshake / feature discovery")
            case .reportingQuery:
                phaseLabel = NSLocalizedString("button_activity_phase_reporting",
                                               comment: "Phase: refreshing per-button conflict state")
            }
            var line = "\(phaseLabel) · \(status.deviceName)"
            if let progress = status.progress {
                line += " · \(progress.current)/\(progress.total)"
            }
            return line
        }.joined(separator: "\n")
    }

    private func makeActivityPopover() -> NSPopover {
        let popover = NSPopover()
        // .applicationDefined: 开合完全由 mouseEnter/Exit 控制, 无点击外部自动关闭的副作用,
        // 和 ButtonTableCellView 冲突图标 popover 行为对齐.
        popover.behavior = .applicationDefined
        popover.animates = true
        let content = ActivityPopoverViewController()
        popover.contentViewController = content
        activityPopoverContent = content
        return popover
    }
}

private extension NSTableView {
    func row(forBinding id: UUID, in bindings: [ButtonBinding]) -> Int? {
        return bindings.firstIndex(where: { $0.id == id })
    }
}

// MARK: - EventRecorderDelegate
extension PreferencesButtonsViewController: KeyRecorderDelegate {
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        let recordedEvent = normalizedRecordedEventForButtonBinding(from: event)
        return !buttonBindings.contains(where: { $0.triggerEvent == recordedEvent })
    }

    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyRecorder.recordingFeedbackDelay(isDuplicate: isDuplicate)) { [weak self] in
            self?.addRecordedEvent(event, isDuplicate: isDuplicate)
        }
    }

    private func normalizedRecordedEventForButtonBinding(from event: InputEvent) -> RecordedEvent {
        let recordedEvent = RecordedEvent(from: event)
        let diagnosis = LogiCenter.shared.buttonCaptureDiagnosis(forMosCode: event.code)
        return recordedEvent.normalizedForButtonBinding(diagnosis: diagnosis)
    }
}
