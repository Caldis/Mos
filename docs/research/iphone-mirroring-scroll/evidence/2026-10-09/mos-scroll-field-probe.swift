import Cocoa

func field(_ n: UInt32) -> CGEventField { CGEventField(rawValue: n)! }
let watched: [UInt32] = [11,12,87,88,93,94,96,97,99,123,137,173,175,176,177,178]
func inspect(_ label: String, _ e: CGEvent) {
    var row: [String] = []
    for n in watched {
        row.append("\(n)=\(e.getDoubleValueField(field(n)))")
    }
    print(label + " " + row.joined(separator: " "))
    if let ne = NSEvent(cgEvent: e) {
        print("  NSEvent precise=\(ne.hasPreciseScrollingDeltas) deltaX=\(ne.deltaX) deltaY=\(ne.deltaY) scrollingDeltaX=\(ne.scrollingDeltaX) scrollingDeltaY=\(ne.scrollingDeltaY) phase=\(ne.phase.rawValue) momentum=\(ne.momentumPhase.rawValue)")
    } else { print("  NSEvent nil") }
}
func make(_ units: CGScrollEventUnit = .line) -> CGEvent {
    CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2, wheel1: 2, wheel2: 3, wheel3: 0)!
}

let a = make()
inspect("line-original", a)
a.setDoubleValueField(field(96), value: 7.5)
a.setDoubleValueField(field(97), value: -8.75)
inspect("public-point-only", a)
a.setDoubleValueField(field(88), value: 1)
inspect("public-continuous", a)
a.setDoubleValueField(field(99), value: 2)
a.setDoubleValueField(field(123), value: 1)
inspect("public-phases", a)
inspect("public-after-copy", a.copy()!)
let b = make(.pixel)
inspect("pixel-original", b)
for (n,v) in [(UInt32(87),91.0),(137,13.0),(173,1.0),(175,101.25),(176,-102.75),(177,201.5),(178,-202.875)] {
    b.setDoubleValueField(field(n), value:v)
}
inspect("private-sentinels", b)
inspect("private-sentinels-copy", b.copy()!)
b.setDoubleValueField(field(96), value: 9.5)
b.setDoubleValueField(field(97), value: -10.75)
b.setDoubleValueField(field(88), value: 1)
b.setDoubleValueField(field(99), value: 4)
b.setDoubleValueField(field(123), value: 2)
inspect("private-plus-mos-public", b)
inspect("private-plus-mos-public-copy", b.copy()!)
for n: UInt32 in [175,176,177,178] {
    let c = make(.pixel)
    c.setDoubleValueField(field(n), value:37.25)
    inspect("isolated-private-\(n)",c)
}
