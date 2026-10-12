// evspy <秒数>: 在 kCGHIDEventTap 只监听除按键外的全部事件类型
// 打印事件类型, sender (87 号字段), 滚动阶段 / 惯性 / 位移, 以及手势子类型字段
import Foundation
import CoreGraphics
setvbuf(stdout, nil, _IOLBF, 0)
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "8") ?? 8
var count = 0
var counts: [UInt32: Int] = [:]
let cb: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return Unmanaged.passUnretained(event) }
    count += 1
    counts[type.rawValue, default: 0] += 1
    let i = { (raw: UInt32) in event.getIntegerValueField(CGEventField(rawValue: raw)!) }
    let d = { (raw: UInt32) in event.getDoubleValueField(CGEventField(rawValue: raw)!) }
    var line = "#\(count) t=\(type.rawValue) sender=\(i(87)) loc=\(Int(event.location.x)),\(Int(event.location.y))"
    switch type.rawValue {
    case 22: // 滚动
        line += " d1=\(i(11)) pt1=\(i(96)) fx1=\(String(format: "%.2f", d(93))) cont=\(i(88)) phase=\(i(99)) mom=\(i(123)) count=\(i(100))"
    case 29, 30, 31, 32: // 手势类事件
        var nz: [String] = []
        for raw in 0...255 where raw != 58 && raw != 169 { guard let f = CGEventField(rawValue: UInt32(raw)) else { continue }; let v = event.getIntegerValueField(f); let dv = event.getDoubleValueField(f); if v != 0 || dv != 0 { nz.append(dv != Double(v) ? "\(raw)=\(v)/\(String(format: "%.4f", dv))" : "\(raw)=\(v)") } }
        line += " gesture nonzero: " + nz.joined(separator: " ")
    case 5, 6, 7, 27: // 鼠标移动 / 拖动
        line += " dx=\(i(4)) dy=\(i(5))"
    default: break
    }
    print(line)
    return Unmanaged.passUnretained(event)
}
let mask = CGEventMask.max & ~((1 << 10) | (1 << 11) | (1 << 12)) // 除按键按下 / 抬起 / 修饰键外的全部事件
guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
                                  eventsOfInterest: mask, callback: cb, userInfo: nil) else { print("TAP_CREATE_FAILED"); exit(3) }
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("EVSPY_READY \(seconds)s")
CFRunLoopRunInMode(.defaultMode, seconds, false)
print("EVSPY_DONE total=\(count) byType=\(counts.sorted { $0.key < $1.key })")
