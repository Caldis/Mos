//
//  MonitorLogStore.swift
//  Mos
//

import Foundation

enum MonitorLogChannel: String, CaseIterable {
    case buttonEvent = "Button Event"
}

final class MonitorLogStore {

    private let previewLineLimit: Int
    private let maxLinesPerChannel: Int
    // 裁剪滞后量: 攒到 max + slack 才批量裁到 max, 避免每次 append 都 O(n) 搬移
    private let trimSlack = 200
    private var linesByChannel: [MonitorLogChannel: [String]] = [:]

    init(previewLineLimit: Int = 200, maxLinesPerChannel: Int = 2000) {
        self.previewLineLimit = max(1, previewLineLimit)
        self.maxLinesPerChannel = max(1, maxLinesPerChannel)
    }

    func append(_ line: String, to channel: MonitorLogChannel) {
        guard !line.isEmpty else { return }
        linesByChannel[channel, default: []].append(line)
        if let count = linesByChannel[channel]?.count, count > maxLinesPerChannel + trimSlack {
            linesByChannel[channel]?.removeFirst(count - maxLinesPerChannel)
        }
    }

    func previewText(for channel: MonitorLogChannel) -> String {
        let lines = linesByChannel[channel] ?? []
        return lines.suffix(previewLineLimit).reversed().joined(separator: "\n")
    }

    func exportText(for channel: MonitorLogChannel) -> String {
        (linesByChannel[channel] ?? []).joined(separator: "\n")
    }

    func clear(_ channel: MonitorLogChannel? = nil) {
        guard let channel else {
            linesByChannel.removeAll()
            return
        }
        linesByChannel[channel] = []
    }
}
