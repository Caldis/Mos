import Cocoa
func field(_ n: UInt32) -> CGEventField { CGEventField(rawValue: n)! }
let watched: [UInt32] = [87,88,96,97,99,123,137,173,175,176,177,178]
func make() -> CGEvent { CGEvent(scrollWheelEvent2Source: nil, units:.pixel, wheelCount:2, wheel1:2, wheel2:3, wheel3:0)! }
func inspect(_ label: String, _ e: CGEvent) {
    let vals = watched.map { "\($0)=\(e.getIntegerValueField(field($0)))/\(e.getDoubleValueField(field($0)))" }
    print(label+" "+vals.joined(separator:" "))
    if let n = NSEvent(cgEvent:e) { print("  NS precise=\(n.hasPreciseScrollingDeltas) scrollingDelta=\(n.scrollingDeltaX),\(n.scrollingDeltaY) phase=\(n.phase.rawValue) momentum=\(n.momentumPhase.rawValue) inverted=\(n.isDirectionInvertedFromDevice)") }
}
for val: Int64 in [0,1,2,3,4,8,16,32,64,128,255] {
    let e=make()
    e.setIntegerValueField(field(173),value:val)
    inspect("only173=\(val)",e)
}
for val: Int64 in [0,1,2,3,4,8] {
    let e=make()
    e.setIntegerValueField(field(123),value:val)
    inspect("only123=\(val)",e)
}
for val: Int64 in [0,1,2,4,8,13] {
    let e=make()
    e.setIntegerValueField(field(137),value:val)
    inspect("only137=\(val)",e)
}
let e=make()
e.setIntegerValueField(field(87),value:0x123456789)
e.setIntegerValueField(field(137),value:1)
e.setIntegerValueField(field(173),value:4)
e.setDoubleValueField(field(175),value:3.25)
e.setDoubleValueField(field(176),value:2.75)
e.setDoubleValueField(field(177),value:8.5)
e.setDoubleValueField(field(178),value:7.625)
let oldStamp=e.timestamp
inspect("sender-tracking-template",e)
let clone=e.copy()!
clone.setDoubleValueField(field(96),value:44.7)
clone.setDoubleValueField(field(97),value:-55.8)
clone.setDoubleValueField(field(88),value:1)
inspect("sender-tracking-mos",clone)
print("timestamp retained \(oldStamp == clone.timestamp) old=\(oldStamp) copy=\(clone.timestamp)")
