//
//  LogitechHIDDebugPanel.swift
//  Mos
//  Logitech HID++ 调试面板 - 显示设备信息和 HID++ 通信日志
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import IOKit
import IOKit.hid

class LogitechHIDDebugPanel: NSObject {
    static let shared = LogitechHIDDebugPanel()

    private var window: NSWindow?
    private var textView: NSTextView?
    private var deviceTableView: NSTableView?
    private var deviceEntries: [(String, String)] = []  // (property, value) pairs
    private var logLines: [String] = []
    private static let maxLogLines = 500
    // 全局日志缓冲 -- 在面板打开前也能收集日志
    private static var logBuffer: [String] = []

    // MARK: - Notification
    static let logNotification = NSNotification.Name("LogitechHIDDebugLog")

    // MARK: - Show / Hide

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        createWindow()
        refreshDevices()
        // 加载历史日志
        for line in LogitechHIDDebugPanel.logBuffer {
            appendLog(line)
        }
        startObserving()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        stopObserving()
        window?.close()
        window = nil
    }

    // MARK: - Logging API (called from LogitechHIDManager/DeviceSession)

    class func log(_ message: String) {
        let timestamp = LogitechHIDDebugPanel.timestamp()
        let line = "[\(timestamp)] \(message)"
        NSLog("[LogitechHID] %@", message)
        // 存入全局缓冲 (面板打开前也能收集)
        logBuffer.append(line)
        if logBuffer.count > maxLogLines {
            logBuffer.removeFirst(logBuffer.count - maxLogLines)
        }
        NotificationCenter.default.post(
            name: LogitechHIDDebugPanel.logNotification,
            object: nil,
            userInfo: ["line": line]
        )
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    // MARK: - Create Window

    private func createWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Logitech HID++ Debug"
        w.center()
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 500, height: 300)

        // Split: top = devices, bottom = log
        let splitView = NSSplitView(frame: w.contentView!.bounds)
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // Top: Device info table
        let deviceScroll = createDeviceTable()
        splitView.addSubview(deviceScroll)

        // Bottom: Log text view
        let logScroll = createLogView()
        splitView.addSubview(logScroll)

        w.contentView?.addSubview(splitView)

        // Toolbar buttons
        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 32))
        toolbar.autoresizingMask = [.width, .minYMargin]

        let refreshBtn = NSButton(title: "Refresh Devices", target: self, action: #selector(refreshButtonClicked))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.frame = NSRect(x: 8, y: 4, width: 130, height: 24)
        toolbar.addSubview(refreshBtn)

        let clearBtn = NSButton(title: "Clear Log", target: self, action: #selector(clearLogClicked))
        clearBtn.bezelStyle = .rounded
        clearBtn.frame = NSRect(x: 146, y: 4, width: 90, height: 24)
        toolbar.addSubview(clearBtn)

        // Adjust layout: toolbar at top, split below
        toolbar.frame = NSRect(x: 0, y: w.contentView!.bounds.height - 32, width: w.contentView!.bounds.width, height: 32)
        splitView.frame = NSRect(x: 0, y: 0, width: w.contentView!.bounds.width, height: w.contentView!.bounds.height - 32)

        w.contentView?.addSubview(toolbar)

        // Set split position (40% devices, 60% log)
        splitView.setPosition(180, ofDividerAt: 0)

        self.window = w
    }

    private func createDeviceTable() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let table = NSTableView()
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 18
        table.delegate = self
        table.dataSource = self

        let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("property"))
        col1.title = "Property"
        col1.width = 200
        table.addTableColumn(col1)

        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        col2.title = "Value"
        col2.width = 480
        table.addTableColumn(col2)

        scrollView.documentView = table
        self.deviceTableView = table
        return scrollView
    }

    private func createLogView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.userFixedPitchFont(ofSize: 11)!
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.textColor = NSColor.textColor
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = tv
        self.textView = tv
        return scrollView
    }

    // MARK: - Device Enumeration

    @objc private func refreshButtonClicked() {
        refreshDevices()
    }

    private func refreshDevices() {
        deviceEntries.removeAll()

        // 直接从 IOKit 枚举所有 Logitech HID devices 及其属性
        guard let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)) as IOHIDManager? else { return }

        let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: 0x046D]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }

        let propertyKeys: [(String, String)] = [
            (kIOHIDProductKey as String, "Product"),
            (kIOHIDVendorIDKey as String, "Vendor ID"),
            (kIOHIDProductIDKey as String, "Product ID"),
            (kIOHIDPrimaryUsagePageKey as String, "Usage Page"),
            (kIOHIDPrimaryUsageKey as String, "Usage"),
            (kIOHIDTransportKey as String, "Transport"),
            (kIOHIDVersionNumberKey as String, "Version"),
            (kIOHIDSerialNumberKey as String, "Serial"),
        ]

        for (i, device) in deviceSet.enumerated() {
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
            deviceEntries.append(("--- Device \(i + 1) ---", name))

            for (key, label) in propertyKeys {
                let value = IOHIDDeviceGetProperty(device, key as CFString)
                let displayValue: String
                if let intVal = value as? Int {
                    if label.contains("ID") || label == "Usage Page" || label == "Usage" {
                        displayValue = String(format: "0x%04X (%d)", intVal, intVal)
                    } else {
                        displayValue = "\(intVal)"
                    }
                } else if let strVal = value as? String {
                    displayValue = strVal
                } else {
                    displayValue = value.map { "\($0)" } ?? "(nil)"
                }
                deviceEntries.append((label, displayValue))
            }

            // HID++ 兼容性判断
            let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            let isBLE = transport.lowercased().contains("bluetooth")
            let isVendorPage = usagePage == 0xFF00 || usagePage == 0xFF43 || usagePage == 0xFFC0
            // BLE 下 HID++ 复用标准 HID 接口 (usage page 0x0001), 所以 BLE + mouse usage 也算兼容
            let isBLEMouse = isBLE && usagePage == 0x0001
            let isHIDPP = isVendorPage || isBLEMouse
            let reason = isVendorPage ? "vendor-specific usage page" : isBLEMouse ? "BLE HID++ over standard HID" : "standard HID, no HID++"
            deviceEntries.append(("HID++ Compatible?", isHIDPP ? "YES (\(reason))" : "NO (\(reason))"))
            deviceEntries.append(("", ""))
        }

        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        deviceTableView?.reloadData()
    }

    // MARK: - Log

    @objc private func clearLogClicked() {
        logLines.removeAll()
        textView?.string = ""
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > LogitechHIDDebugPanel.maxLogLines {
            logLines.removeFirst(logLines.count - LogitechHIDDebugPanel.maxLogLines)
        }
        if let tv = textView {
            let shouldScroll = tv.enclosingScrollView?.verticalScroller?.floatValue ?? 0 > 0.95
            tv.textStorage?.append(NSAttributedString(
                string: line + "\n",
                attributes: [
                    .font: NSFont.userFixedPitchFont(ofSize: 11)!,
                    .foregroundColor: NSColor.textColor
                ]
            ))
            if shouldScroll {
                tv.scrollToEndOfDocument(nil)
            }
        }
    }

    // MARK: - Observers

    private var logObserver: NSObjectProtocol?
    private var deviceObserver: NSObjectProtocol?

    private func startObserving() {
        logObserver = NotificationCenter.default.addObserver(
            forName: LogitechHIDDebugPanel.logNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let line = notification.userInfo?["line"] as? String {
                self?.appendLog(line)
            }
        }
        // 设备插拔时自动刷新
        deviceObserver = NotificationCenter.default.addObserver(
            forName: LogitechHIDManager.buttonEventNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    private func stopObserving() {
        if let obs = logObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = deviceObserver { NotificationCenter.default.removeObserver(obs) }
        logObserver = nil
        deviceObserver = nil
    }
}

// MARK: - NSTableViewDelegate & DataSource
extension LogitechHIDDebugPanel: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return deviceEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = deviceEntries[row]
        let text: String
        if tableColumn?.identifier.rawValue == "property" {
            text = entry.0
        } else {
            text = entry.1
        }

        let cellId = NSUserInterfaceItemIdentifier("DebugCell")
        let cell: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = cellId
            cell.font = NSFont.userFixedPitchFont(ofSize: 11)!
            cell.lineBreakMode = .byTruncatingTail
        }

        cell.stringValue = text
        // Section headers bold
        if entry.0.hasPrefix("---") {
            cell.font = NSFont.boldSystemFont(ofSize: 11)
        } else {
            cell.font = NSFont.userFixedPitchFont(ofSize: 11)!
        }
        return cell
    }
}
