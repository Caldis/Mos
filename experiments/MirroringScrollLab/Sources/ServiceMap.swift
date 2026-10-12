// HID 服务与设备属性快照: 记录当轮镜像可能读到的设备身份与属性
//
// CGEvent 的 87 号字段是产生该事件的 IOHIDEventService 注册表 ID, 快照以该 ID 为键, 使帧日志可以回查设备。
// 属性取自设备注册表内容, 键名是注册表里的实际拼写 (DeviceTypeHint, SupportsGestureScrolling, HIDScrollResolution
// 等); UniversalHID 的 HIDServiceProperties 符号名只用于在 scroll_props 中挑出滚动相关项, 见
// evidence/2026-10-09/sdk-and-service-properties.txt

import AppKit
import Foundation
import IOKit

enum ServiceMap {
    /// 顶层键命中任一关键词即收入 scroll_props。注册表键的拼写不统一 (HIDScrollResolution / DeviceTypeHint),
    /// 因此按关键词匹配而不是逐个键名
    private static let scrollTokens = ["scroll", "accel", "gesture", "devicetype", "remote", "report"]
    /// UniversalHID 的 HIDServiceProperties 对应注册表里的 HIDEventServiceProperties, 无论键名是否命中关键词都保留
    private static let alwaysKeep = ["HIDEventServiceProperties"]
    /// 驱动注册与事件传递无关的管道属性, 每台设备都有且内容相同
    private static let plumbing: Set<String> = [
        "IOCFPlugInTypes", "IOGeneralInterest", "IOMatchedPersonality", "IOServiceDEXTEntitlements",
        "IOUserClientClass", "IOUserServerCDHash", "IOUserServerName", "IOUserServerOneProcess",
        "IOUserClasses", "IOUserClass", "IOClass", "IOProbeScore", "IOProviderClass", "IOMatchCategory",
        "IOPowerManagement", "IOPersonalityPublisher", "CFBundleIdentifier", "CFBundleIdentifierKernel",
    ]

    /// app 所在工作树的 git 版本。证据里的字段语义随代码变化, 没有这一项就无法判断某轮记录对应哪一版
    static var source: [String: Any] {
        var url = URL(fileURLWithPath: Bundle.main.bundlePath)
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                var out: [String: Any] = ["root": url.path]
                out["revision"] = git(["rev-parse", "--short", "HEAD"], at: url) ?? "unknown"
                out["branch"] = git(["rev-parse", "--abbrev-ref", "HEAD"], at: url) ?? "unknown"
                return out
            }
            if url.path == "/" { break }
        }
        return ["root": "unknown", "revision": "unknown", "branch": "unknown"]
    }

    private static func git(_ arguments: [String], at root: URL) -> String? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func snapshot() -> [String: Any] {
        // 已出现过的 sender 是判定输入设备的直接依据: 87 号字段命中的服务一定会被展开
        var senders = Lab.ownSenders.get()
        senders.formUnion(VirtualMagicTrackpad.serviceIDs.get())
        if let id = MultitouchSender.id { senders.insert(id) }
        for id in [Lab.lastTrackpadSender.get(), Lab.lastMouseSender.get()] where id != 0 { senders.insert(id) }
        var services: [[String: Any]] = []
        for className in ["IOHIDEventService", "AppleMultitouchDevice"] {
            services += enumerate(className, senders: senders)
        }
        var out: [String: Any] = [
            "t": Date().timeIntervalSince1970,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "app": Recorder.appVersion,
            "sdk": Bundle.main.infoDictionary?["DTSDKName"] as? String ?? "unknown",
            "built": builtDate,
            "natural_scrolling": (UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool) ?? true,
            "learned_trackpad_sender": Lab.lastTrackpadSender.get(),
            "learned_mouse_sender": Lab.lastMouseSender.get(),
            "own_senders": Lab.ownSenders.get().sorted(),
            "virtual_magic_trackpad_senders": VirtualMagicTrackpad.serviceIDs.get().sorted(),
            "mirroring": mirroringState(),
            "source": source,
            "services": services,
        ]
        out["multitouch_sender"] = MultitouchSender.id.map { $0 as Any } ?? NSNull()
        return out
    }

    /// app 二进制的构建时间; 证据目录里的代码版本由工作树快照记录, 这里只用于确认跑的是哪一次构建
    private static var builtDate: String {
        guard let path = Bundle.main.executableURL?.path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return "unknown" }
        let f = ISO8601DateFormatter()
        return f.string(from: date)
    }

    private static func mirroringState() -> [String: Any] {
        let m = MirroringLocator.shared.state.get()
        var out: [String: Any] = ["frontmost": m.frontmost]
        out["pid"] = m.pid.map { Int($0) } ?? NSNull()
        if let r = m.rect { out["rect"] = [r.minX, r.minY, r.width, r.height] }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity").first
        out["version"] = app?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? NSNull()
        return out
    }

    private static func enumerate(_ className: String, senders: Set<Int64>) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var out: [[String: Any]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let entry = describe(service, className: className, senders: senders) { out.append(entry) }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return out
    }

    private static func describe(_ service: io_object_t, className: String, senders: Set<Int64>) -> [String: Any]? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }
        var name = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(service, &name)

        var properties: [String: Any] = [:]
        var unmanaged: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let dict = unmanaged?.takeRetainedValue() as? [String: Any] {
            for (key, value) in dict where !plumbing.contains(key) {
                // 普通属性里的容器只留结构 (键名 / 条目数), 完整内容按需在 scroll_props 中展开
                if let converted = convert(value, depth: 0, full: false) { properties[key] = converted }
            }
        }

        let usagePage = properties["PrimaryUsagePage"] as? Int ?? 0
        let usage = properties["PrimaryUsage"] as? Int ?? 0
        let product = properties["Product"] as? String ?? ""
        // 输入设备的判定: 触控板类服务, 通用桌面页的指针与鼠标用途, 数字转换器页, 已知 sender,
        // 以及产品名带 Trackpad / Mouse / Magic 的设备。其余 IOHIDEventService (电源管理轨道等) 只留摘要
        let isInput = className == "AppleMultitouchDevice"
            || (usagePage == 1 && (usage == 1 || usage == 2))
            || usagePage == 0x0D
            || senders.contains(Int64(bitPattern: entryID))
            || ["Trackpad", "Mouse", "Magic"].contains(where: { product.contains($0) })

        var scroll: [String: Any] = [:]
        var unmanagedFull: Unmanaged<CFMutableDictionary>?
        var raw: [String: Any] = [:]
        if IORegistryEntryCreateCFProperties(service, &unmanagedFull, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let dict = unmanagedFull?.takeRetainedValue() as? [String: Any] {
            raw = dict
        }
        for (key, value) in properties {
            let lower = key.lowercased()
            let byToken = scrollTokens.contains(where: { lower.contains($0) })
            guard byToken || (isInput && alwaysKeep.contains(key)) else { continue }
            scroll[key] = isInput ? (raw[key].flatMap { convert($0, depth: 0, full: true) } ?? value) : value
        }

        var out: [String: Any] = [
            "class": className,
            "registry_id": Int64(bitPattern: entryID),
            "name": String(cString: name),
        ]
        for key in ["Product", "VendorID", "ProductID", "Transport", "PrimaryUsagePage", "PrimaryUsage", "LocationID", "ReportInterval"] {
            if let v = properties[key] { out[snake(key)] = v }
        }
        out["input_device"] = isInput
        out["scroll_props"] = scroll
        out["props"] = properties
        return out
    }

    private static func snake(_ key: String) -> String {
        switch key {
        case "Product": return "product"
        case "VendorID": return "vendor_id"
        case "ProductID": return "product_id"
        case "Transport": return "transport"
        case "PrimaryUsagePage": return "primary_usage_page"
        case "PrimaryUsage": return "primary_usage"
        case "LocationID": return "location_id"
        case "ReportInterval": return "report_interval"
        default: return key
        }
    }

    /// 注册表属性转 JSON 可编码的值。二进制描述符只留长度与前 64 字节, 完整内容可用 hidutil 重新导出;
    /// `full` 为假时容器只记录结构, 为真 (scroll_props) 时展开并限制条目数与深度
    private static func convert(_ value: Any, depth: Int, full: Bool) -> Any? {
        let cf = value as CFTypeRef
        switch CFGetTypeID(cf) {
        case CFBooleanGetTypeID():
            return (value as? NSNumber)?.boolValue ?? false
        case CFNumberGetTypeID():
            return value as? NSNumber
        case CFStringGetTypeID():
            guard let s = value as? String else { return nil }
            return s.count > 400 ? String(s.prefix(400)) + "…" : s
        case CFDataGetTypeID():
            guard let data = value as? Data else { return nil }
            return ["len": data.count, "head_hex": data.prefix(64).map { String(format: "%02x", $0) }.joined()]
        case CFArrayGetTypeID():
            guard depth < 3, let array = value as? [Any] else { return ["truncated": true] }
            guard full else { return ["count": array.count] }
            return array.prefix(32).compactMap { convert($0, depth: depth + 1, full: full) }
        case CFDictionaryGetTypeID():
            guard let dict = value as? [String: Any] else { return ["truncated": true] }
            guard full, depth < 3 else { return ["keys": dict.keys.sorted()] }
            var out: [String: Any] = [:]
            for (key, item) in dict.sorted(by: { $0.key < $1.key }).prefix(64) {
                if let converted = convert(item, depth: depth + 1, full: full) { out[key] = converted }
            }
            return out
        default:
            return String(describing: value).prefix(200).description
        }
    }
}
