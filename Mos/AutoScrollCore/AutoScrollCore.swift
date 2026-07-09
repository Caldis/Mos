//
//  AutoScrollCore.swift
//  Mos
//  自动滚动核心类 - 中键点击激活自动滚动
//  Created by Auto-Scroll Implementation on 2025/11/29.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class AutoScrollCore {

    // 单例
    static let shared = AutoScrollCore()
    init() { NSLog("Module initialized: AutoScrollCore") }

    // MARK: - 状态管理

    // 自动滚动激活状态
    var isActive = false

    // 中键按下检测状态
    var middleButtonPressed = false
    var pressLocation: CGPoint?
    var pressTime: Date?

    // 滚动原点和当前点
    var originPoint: CGPoint?
    var currentPoint: CGPoint?

    // 计时器
    var scrollTimer: Timer?

    // 覆盖窗口（显示固定图标）
    var overlay: AutoScrollOverlay?

    // MARK: - 设置（独立于常规滚动设置）

    // 灵敏度（0.2x - 3.0x）
    var sensitivity: Double {
        get { Options.shared.autoScroll.sensitivity }
        set { Options.shared.autoScroll.sensitivity = newValue }
    }

    // 死区大小（像素）- 在此范围内不滚动
    var deadZone: CGFloat {
        get { Options.shared.autoScroll.deadZone }
    }

    // 拖动阈值（像素）- 超过此距离视为拖动而非点击
    var dragThreshold: CGFloat {
        get { Options.shared.autoScroll.dragThreshold }
    }

    // 最大滚动速度
    var maxSpeed: CGFloat {
        get { Options.shared.autoScroll.maxSpeed }
    }

    // 是否启用
    var isEnabled: Bool {
        get { Options.shared.autoScroll.enabled }
    }

    // MARK: - 事件处理

    /// 处理中键按下事件
    /// - Returns: true if event should be consumed (in blocked area), false if should pass through
    func handleMiddleButtonDown(at point: CGPoint) -> Bool {
        guard isEnabled else { return false }

        // Check if we're in a blocked area (tabs/bookmarks)
        let browserInfo = getBrowserWindowInfo(at: point)
        if browserInfo.isInUIArea {
            return false  // Don't consume - let bookmark/tab click work normally
        }

        middleButtonPressed = true
        pressLocation = point
        pressTime = Date()

        return false  // Pass through to let button up handler decide
    }

    /// 处理鼠标移动事件（用于拖动检测）
    func handleMouseMove(to point: CGPoint) {
        guard middleButtonPressed, let pressLoc = pressLocation else { return }

        // 计算移动距离
        let dx = point.x - pressLoc.x
        let dy = point.y - pressLoc.y
        let distance = sqrt(dx * dx + dy * dy)

        // 如果移动距离超过阈值，则标记为拖动操作
        if distance > dragThreshold {
            middleButtonPressed = false
            pressLocation = nil
        }
    }

    /// 处理中键释放事件
    /// - Returns: true if event was handled (activated OR blocked), false if event should pass through
    func handleMiddleButtonUp(at point: CGPoint) -> Bool {
        guard isEnabled else { return false }

        // CRITICAL FIX: ALWAYS stop existing timer/active scroll on ANY middle-button UP
        // Even if middleButtonPressed is false (blocked DOWN), we need to stop any existing scroll
        if scrollTimer != nil || isActive {
            stopAutoScroll()
            middleButtonPressed = false
            pressLocation = nil
            return true  // Consumed - we stopped an existing scroll
        }

        guard middleButtonPressed, let pressLoc = pressLocation else { return false }

        // 计算点击期间的移动距离
        let dx = point.x - pressLoc.x
        let dy = point.y - pressLoc.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance <= dragThreshold {
            // 是点击而非拖动 - 切换自动滚动状态

            // ALWAYS stop timer if it exists, regardless of isActive state
            if scrollTimer != nil {
                stopAutoScroll()
            } else if isActive {
                stopAutoScroll()
            } else if !isActive && scrollTimer == nil {
                // Not active and no timer - safe to proceed with activation check

                // 检查是否应该激活自动滚动
                let shouldActivate = shouldActivateAutoScroll(at: point)

                // Write to a debug file for easy checking

                if shouldActivate {

                    // TRIPLE CHECK before actually starting
                    let browserInfo = getBrowserWindowInfo(at: point)
                    if browserInfo.isInUIArea {
                        return true  // Consume event to prevent Chrome's auto-scroll
                    }

                    startAutoScroll(at: point)
                } else {
                    // CRITICAL: Force stop everything to prevent ghost scrolling
                    stopAutoScroll()

                    // Extra safety: ensure timer is killed and state is cleared
                    scrollTimer?.invalidate()
                    scrollTimer = nil
                    originPoint = nil
                    currentPoint = nil
                    isActive = false

                    return false  // Don't consume - let link clicks pass through to browser
                }
            }
        } else {
        }

        middleButtonPressed = false
        pressLocation = nil
        pressTime = nil
        return false  // Let event pass through (drag or normal click)
    }

    // MARK: - Scrollable Area Detection

    /// 检查是否应该在给定位置激活自动滚动
    func shouldActivateAutoScroll(at point: CGPoint) -> Bool {

        // 先检查是否在浏览器窗口或其他应用
        let browserInfo = getBrowserWindowInfo(at: point)


        // 如果在任何应用的UI区域（标题栏、书签栏等），直接阻止
        if browserInfo.isInUIArea {
            return false
        }

        // 浏览器使用严格模式，其他应用使用宽松模式
        let strictMode = browserInfo.isBrowser

        let hasScrollable = hasScrollableContent(at: point, strictMode: strictMode)

        return hasScrollable
    }

    // MARK: - Browser Detection

    /// 浏览器窗口信息
    struct BrowserWindowInfo {
        let isBrowser: Bool
        let name: String?
        let isInUIArea: Bool
    }

    /// 获取浏览器窗口信息
    func getBrowserWindowInfo(at point: CGPoint) -> BrowserWindowInfo {
        var logText = "\n=== getBrowserWindowInfo at \(point) ===\n"

        // Convert NSScreen coordinates (Y=0 at bottom) to CGWindow coordinates (Y=0 at top)
        // CRITICAL: Use screens.first (primary screen) not .main (focused screen)
        let cgPoint: CGPoint
        if let primaryScreen = NSScreen.screens.first {
            cgPoint = CGPoint(x: point.x, y: primaryScreen.frame.height - point.y)
            logText += "Primary screen height: \(primaryScreen.frame.height)\n"
            logText += "NSScreen: (\(point.x), \(point.y)) -> CGWindow: (\(cgPoint.x), \(cgPoint.y))\n"
        } else {
            cgPoint = point
            logText += "WARNING: No primary screen!\n"
        }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]

        guard let windows = windowList else {
            logText += "ERROR: No window list!\n"
            return BrowserWindowInfo(isBrowser: false, name: nil, isInUIArea: false)
        }

        logText += "Total windows: \(windows.count)\n\n"

        // 找到点击位置的窗口
        for (index, window) in windows.enumerated() {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"] else {
                continue
            }

            let ownerName = window[kCGWindowOwnerName as String] as? String ?? "unknown"
            let windowName = window[kCGWindowName as String] as? String ?? "no name"

            // Skip system windows that cover the entire screen
            let systemWindows = ["Dock", "Window Server", "Spotlight", "Control Center", "SystemUIServer"]
            if systemWindows.contains(ownerName) {
                continue
            }

            if index < 10 { // Log first 10 windows to file
                logText += "Window \(index): \(ownerName)\n"
                logText += "  Name: \(windowName)\n"
                logText += "  Bounds: x=\(x), y=\(y), w=\(width), h=\(height)\n"

                // Check if point is in bounds
                let inBounds = cgPoint.x >= x && cgPoint.x <= x + width && cgPoint.y >= y && cgPoint.y <= y + height
                logText += "  Point in bounds: \(inBounds)\n\n"

            }

            // Check if point is in this window
            if cgPoint.x >= x && cgPoint.x <= x + width &&
               cgPoint.y >= y && cgPoint.y <= y + height {

                logText += "\n✓✓✓ FOUND WINDOW AT POINT ✓✓✓\n"
                logText += "Window: \(ownerName)\n"
                logText += "Point: (\(cgPoint.x), \(cgPoint.y))\n"
                logText += "Bounds: (\(x), \(y), \(width), \(height))\n\n"

                // 检查是否是浏览器窗口 - 使用更精确的匹配
            let browserChecks = [
                ("Google Chrome", ownerName == "Google Chrome" || ownerName == "Chrome" || ownerName.contains("Chrome")),
                ("Chromium", ownerName == "Chromium"),
                ("Safari", ownerName == "Safari"),
                ("Firefox", ownerName == "Firefox" || ownerName.contains("Firefox")),
                ("Microsoft Edge", ownerName.contains("Edge")),  // Matches "Edge", "Edge Dev", "Edge Beta", etc.
                ("Brave Browser", ownerName.contains("Brave")),
                ("Opera", ownerName == "Opera"),
                ("Arc", ownerName == "Arc"),
                ("Vivaldi", ownerName == "Vivaldi")
            ]

            var isBrowserWindow = false
            var browserName = ""

            for (name, matches) in browserChecks {
                if matches {
                    isBrowserWindow = true
                    browserName = name
                    break
                }
            }

            let relativeY = cgPoint.y - y

            if isBrowserWindow {
                // Browser UI: Only block actual UI areas
                // Top: 130px (tabs ~40px + address bar ~50px + bookmarks bar ~40px)
                // Bottom: 50px (status bar, download bar)
                let topUIHeight: CGFloat = 130.0
                let bottomUIHeight: CGFloat = 50.0
                let isInUI = relativeY < topUIHeight || relativeY > height - bottomUIHeight

                logText += "Browser detected: \(browserName)\n"
                logText += "relativeY: \(relativeY), topUI: \(topUIHeight), isInUI: \(isInUI)\n"

                return BrowserWindowInfo(isBrowser: true, name: browserName, isInUIArea: isInUI)
            } else {
                // 非浏览器应用：阻止顶部区域（标题栏、工具栏）
                // 固定120px（标题栏~40px + 工具栏~80px）
                let uiHeight: CGFloat = 120.0
                if relativeY < uiHeight {

                    logText += "Non-browser: \(ownerName)\n"
                    logText += "relativeY: \(relativeY), uiHeight: \(uiHeight), isInUI: true\n"

                    return BrowserWindowInfo(isBrowser: false, name: ownerName, isInUIArea: true)
                }
            }

                break  // Found the window at point
            }  // End of point-in-window check
        }  // End of for loop

        logText += "\nNO WINDOW FOUND AT POINT!\n"

        return BrowserWindowInfo(isBrowser: false, name: nil, isInUIArea: false)
    }

    /// 检查点击位置是否有可滚动内容
    /// - Parameters:
    ///   - point: 点击位置
    ///   - strictMode: 严格模式（用于浏览器），宽松模式（用于其他应用）
    func hasScrollableContent(at point: CGPoint, strictMode: Bool) -> Bool {
        // Convert to macOS coordinate system (Y-axis from bottom to top)
        // CRITICAL: Use screens.first (primary screen) not .main (focused screen)
        guard let primaryScreen = NSScreen.screens.first else {
            return !strictMode // Strict mode returns false, lenient mode returns true
        }

        let screenHeight = primaryScreen.frame.height
        let axPoint = CGPoint(x: point.x, y: screenHeight - point.y)

        // Try multiple methods to get the element at point
        var element: AXUIElement?

        // Method 1: System-wide element
        element = getElementAtPoint(axPoint)

        // Method 2: If we got a scroll area, try getting element via the frontmost app
        if strictMode, let frontApp = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
            if let appPointElement = getElementAtPointViaApp(axPoint, appElement: appElement) {
                let role = getRole(of: appPointElement)

                // If the app-level query gives us a more specific element, use it
                if role != "AXScrollArea" && role != nil {
                    element = appPointElement
                }
            }
        }

        guard let element = element else {
            return !strictMode // 严格模式返回false，宽松模式返回true
        }

        // CRITICAL: In browsers, check for clickable elements
        if strictMode {

            // Note: Link detection removed - now handled by cursor detection in ButtonCore.swift
            // Accessibility APIs don't work for Chromium browsers' web content
        }

        // 检查元素及其父元素链
        var current: AXUIElement? = element
        var depth = 0
        let maxDepth = 15
        var foundAnyScrollableHint = false
        var foundBlockingElement = false

        while let elem = current, depth < maxDepth {
            let role = getRole(of: elem)
            let hasScrollBars = hasScrollBars(elem)


            // 如果找到滚动条，标记为可能可滚动
            if hasScrollBars {
                foundAnyScrollableHint = true
            }

            // 检查是否是可滚动的元素类型
            if let r = role {
                // 可滚动区域 - 立即返回true (links already checked above)
                if r == kAXScrollAreaRole as String ||
                   r == "AXWebArea" ||
                   r == kAXTextAreaRole as String ||
                   r == "AXGroup" && hasScrollBars ||
                   r == "AXSplitGroup" || // VS Code使用分割组
                   r == "AXList" && hasScrollBars || // 列表如果有滚动条
                   r == "AXTable" && hasScrollBars || // 表格如果有滚动条
                   r == "AXOutline" && hasScrollBars { // 大纲视图如果有滚动条
                    return true
                }

                // Blocking UI elements (non-link)
                if r == kAXButtonRole as String ||
                   r == kAXToolbarRole as String ||
                   r == "AXTabGroup" ||
                   r == kAXRadioButtonRole as String ||
                   r == kAXMenuRole as String ||
                   r == kAXMenuItemRole as String ||
                   r == "AXPopUpButton" { // 下拉按钮
                    foundBlockingElement = true
                    // 继续检查，可能父元素是可滚动的
                }
            }

            // 尝试获取父元素
            current = getParentElement(of: elem)
            depth += 1
        }

        // 如果找到滚动条，允许激活
        if foundAnyScrollableHint {
            return true
        }

        // 严格模式：必须找到明确的可滚动内容
        if strictMode {
            // 如果找到阻止元素，拒绝
            if foundBlockingElement {
                return false
            }
            // 没找到明确的可滚动内容，拒绝
            return false
        }

        // 宽松模式：如果找到阻止元素，拒绝
        if foundBlockingElement {
            return false
        }

        // 宽松模式：即使没找到明确的scrollArea，但如果遍历了足够的层级且没有UI元素，
        // 说明在内容区域（VS Code编辑器等），允许激活
        // 这是因为某些应用的accessibility信息不完整
        if depth >= 8 {
            return true
        }

        // 层级较浅且没找到scrollable内容，可能在非内容区域
        return false
    }

    // MARK: - Accessibility Helpers

    /// 获取指定点的可访问性元素
    func getElementAtPoint(_ point: CGPoint) -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)

        if result == .success {
            return element
        }
        return nil
    }

    /// 获取元素的角色
    func getRole(of element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)

        if result == .success, let role = value as? String {
            return role
        }
        return nil
    }

    // MARK: - Removed Obsolete Link Detection
    // Previous attempts using accessibility APIs (getURL, getSubrole, getDescription, isActionableElement)
    // were removed because Chromium browsers don't expose web content via macOS accessibility APIs.
    // Current solution uses cursor detection (see ButtonCore.swift)

    /// 获取父元素
    func getParentElement(of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)

        if result == .success {
            return (value as! AXUIElement)
        }
        return nil
    }

    /// 检查元素是否有滚动条
    func hasScrollBars(_ element: AXUIElement) -> Bool {
        // 检查垂直滚动条
        var verticalScrollBar: AnyObject?
        let vResult = AXUIElementCopyAttributeValue(element, "AXVerticalScrollBar" as CFString, &verticalScrollBar)

        // 检查水平滚动条
        var horizontalScrollBar: AnyObject?
        let hResult = AXUIElementCopyAttributeValue(element, "AXHorizontalScrollBar" as CFString, &horizontalScrollBar)

        return vResult == .success || hResult == .success
    }

    /// Get children of an accessibility element
    /// Tries multiple attributes since browsers may use different ones
    func getChildren(of element: AXUIElement) -> [AXUIElement]? {
        // Try standard children attribute first
        var value: AnyObject?
        var result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)

        if result == .success, let children = value as? [AXUIElement], !children.isEmpty {
            return children
        }

        // Try AXContents (used by some browsers for web content)
        result = AXUIElementCopyAttributeValue(element, "AXContents" as CFString, &value)
        if result == .success, let children = value as? [AXUIElement], !children.isEmpty {
            return children
        }

        // Try AXVisibleChildren
        result = AXUIElementCopyAttributeValue(element, kAXVisibleChildrenAttribute as CFString, &value)
        if result == .success, let children = value as? [AXUIElement], !children.isEmpty {
            return children
        }

        return nil
    }

    /// Get the focused element within an application - browsers often have the link as focused
    func getFocusedElement(from element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &value)

        if result == .success {
            return (value as! AXUIElement)
        }
        return nil
    }

    /// Get the element at position using the application element instead of system-wide
    /// This sometimes gives more accurate results for web content
    func getElementAtPointViaApp(_ point: CGPoint, appElement: AXUIElement) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &element)

        if result == .success {
            return element
        }
        return nil
    }

    /// Get the frame/position of an accessibility element
    func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard posResult == .success, sizeResult == .success else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        if let posValue = positionValue {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        }
        if let szValue = sizeValue {
            AXValueGetValue(szValue as! AXValue, .cgSize, &size)
        }

        return CGRect(origin: position, size: size)
    }

    /// Find the deepest element at a given point by drilling into children
    func findDeepestElementAtPoint(_ element: AXUIElement, point: CGPoint) -> AXUIElement {
        guard let children = getChildren(of: element), !children.isEmpty else {
            return element
        }


        // Check each child to see if the point is within its bounds
        for (index, child) in children.enumerated() {
            let role = getRole(of: child) ?? "unknown"
            if let frame = getElementFrame(child) {
                let contains = frame.contains(point)
                if index < 5 || role == "AXLink" {  // Log first 5 and any links
                }
                if contains {
                    // Recursively drill down
                    return findDeepestElementAtPoint(child, point: point)
                }
            } else {
                if index < 3 {
                }
            }
        }

        // No child contains the point, return current element
        return element
    }

    /// Check if there's a link at or near the given point within the element's children
    /// This searches the accessibility tree for AXLink elements
    func hasLinkAtPoint(_ element: AXUIElement, point: CGPoint, depth: Int) -> Bool {
        // Limit recursion depth
        guard depth < 15 else { return false }

        let role = getRole(of: element)

        // Log at shallow depths
        if depth < 4 {
            let childCount = getChildren(of: element)?.count ?? 0
        }

        // Check if this element is a link
        if role == "AXLink" {
            // Check if point is within this element's bounds
            if let frame = getElementFrame(element) {
                if frame.contains(point) {
                    return true
                }
            } else {
                // If we can't get the frame, assume the link is at the point (conservative)
                return true
            }
        }

        // Check children
        guard let children = getChildren(of: element), !children.isEmpty else {
            return false
        }

        for child in children {
            // Only check children whose bounds might contain the point
            if let frame = getElementFrame(child) {
                // Expand the check area slightly for tolerance
                let expandedFrame = frame.insetBy(dx: -5, dy: -5)
                if expandedFrame.contains(point) || depth < 3 {
                    if hasLinkAtPoint(child, point: point, depth: depth + 1) {
                        return true
                    }
                }
            } else {
                // If we can't get frame, still check if depth is shallow
                if depth < 3 {
                    if hasLinkAtPoint(child, point: point, depth: depth + 1) {
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - 自动滚动控制

    /// 启动自动滚动
    func startAutoScroll(at point: CGPoint) {

        // RE-CHECK: Verify we should actually start
        let recheck = shouldActivateAutoScroll(at: point)
        if !recheck {
            let criticalError = "CRITICAL BUG: startAutoScroll called at \(point) but shouldActivate=false at \(Date())\n"
            return
        }

        // Write to debug
        let startInfo = "startAutoScroll called at \(point) at \(Date())\n"

        // 停止任何现有的滚动
        stopAutoScroll()

        // 设置原点
        originPoint = point
        isActive = true

        // 创建并显示固定图标覆盖层
        if overlay == nil {
            overlay = AutoScrollOverlay()
        }
        overlay?.show(at: point)

        // 启动滚动计时器（每10ms触发一次）
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            self?.performScroll()
        }

        // 添加到主运行循环
        if let timer = scrollTimer {
            RunLoop.current.add(timer, forMode: .common)
        }

    }

    /// 停止自动滚动
    func stopAutoScroll() {
        // 停止计时器
        if let timer = scrollTimer {
            timer.invalidate()
        }
        scrollTimer = nil

        // 隐藏覆盖层
        overlay?.hide()

        // 重置状态
        isActive = false
        originPoint = nil
        currentPoint = nil

    }

    /// 执行滚动（由计时器调用）
    func performScroll() {
        // 安全检查：确保auto-scroll已激活
        guard isActive else { return }
        guard let origin = originPoint else { return }

        // 获取当前鼠标位置
        let current = NSEvent.mouseLocation

        // NOTE: We do NOT check if mouse moves into UI area during scroll
        // The UI area check is only done on initial click
        // Once scrolling is active, we allow the mouse to move anywhere
        // This lets users move mouse up (into bookmarks area) to scroll down

        // 计算与原点的垂直距离
        let deltaY = current.y - origin.y
        let deltaX = current.x - origin.x

        // 计算总距离（使用勾股定理）
        let totalDistance = sqrt(deltaX * deltaX + deltaY * deltaY)

        // 必须至少移动10像素才开始滚动
        if totalDistance < 10.0 {
            return // 鼠标还在原点附近，不滚动
        }

        // 死区处理
        let effectiveDistance = abs(deltaY) - deadZone
        if effectiveDistance <= 0 {
            return // 在死区内，不滚动
        }

        // 计算滚动方向（1 = 向下，-1 = 向上）- 反转以匹配自然滚动
        let direction: CGFloat = deltaY > 0 ? 1.0 : -1.0

        // 二次加速：滚动速度随距离增加而加速
        // 使用 maxSpeed 作为基准，距离越大速度越快
        let normalizedDistance = effectiveDistance / 100.0  // 标准化距离
        let acceleration = pow(normalizedDistance, 1.8)  // 非线性加速
        let scrollSpeed = min(acceleration * maxSpeed * 0.5, maxSpeed)

        // 应用灵敏度
        // 对于低速（<1.0），使用指数缩放使其更慢
        let adjustedSensitivity: CGFloat
        if sensitivity < 1.0 {
            adjustedSensitivity = CGFloat(pow(sensitivity, 1.5))
        } else {
            adjustedSensitivity = CGFloat(sensitivity)
        }

        let finalAmount = direction * scrollSpeed * adjustedSensitivity

        // 阈值检查 - 避免无意义的滚动
        let threshold = min(0.1, adjustedSensitivity * 0.5)
        if abs(finalAmount) < threshold {
            return
        }

        // 创建并发送滚动事件
        // 使用特殊标志来标记这是自动滚动事件，避免被 ScrollCore 处理
        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(finalAmount),
            wheel2: 0,
            wheel3: 0
        ) {
            // 使用 maskAlternate 标志来标记自动滚动事件
            // ScrollCore 会检测到这个标志并直接放行，不做平滑处理
            scrollEvent.flags = [.maskAlternate, .maskNonCoalesced]
            scrollEvent.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - 应用例外处理

    /// 检查当前应用是否应该禁用自动滚动
    func shouldEnableForCurrentApp() -> Bool {
        // TODO: 实现应用例外列表检查
        return isEnabled
    }

    /// 获取当前应用的拖动阈值
    func getDragThresholdForCurrentApp() -> CGFloat {
        // TODO: 实现应用特定的拖动阈值
        return dragThreshold
    }
}
