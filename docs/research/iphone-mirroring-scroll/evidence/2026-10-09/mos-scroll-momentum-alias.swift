import Cocoa
func f(_ n:UInt32)->CGEventField { CGEventField(rawValue:n)! }
func make()->CGEvent { CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:2,wheel2:3,wheel3:0)! }
func row(_ name:String,_ e:CGEvent) { print("\(name): scroll99=\(e.getIntegerValueField(f(99))) momentum123=\(e.getIntegerValueField(f(123))) option173=\(e.getIntegerValueField(f(173))) a175=\(e.getDoubleValueField(f(175))) a176=\(e.getDoubleValueField(f(176))) r177=\(e.getDoubleValueField(f(177))) r178=\(e.getDoubleValueField(f(178)))") }
let e=make()
e.setIntegerValueField(f(173),value:0x30|2)
row("base-highflags",e)
e.setIntegerValueField(f(123),value:1)
row("set-momentum123",e)
e.setIntegerValueField(f(99),value:2)
row("set-scroll99",e)
e.setDoubleValueField(f(88),value:0)
row("set-continuous0",e)
e.timestamp=123456789
let c=e.copy()!
print("copy-timestamp \(c.timestamp)")
