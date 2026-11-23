import Cocoa

struct MonitorButtonEvent {
    private enum Details {
        case mouse(button: UInt16, x: Int64, y: Int64, userData: Int64)
        case key(code: UInt16, phase: String?)
    }

    let time: CFTimeInterval
    private let name: String
    private let modifiers: String
    private let flags: UInt64
    private let details: Details

    init?(_ event: CGEvent) {
        if event.isMouseInteractionEvent {
            details = .mouse(
                button: event.mouseCode,
                x: event.getIntegerValueField(.mouseEventDeltaX),
                y: event.getIntegerValueField(.mouseEventDeltaY),
                userData: event.getIntegerValueField(.eventSourceUserData)
            )
        } else if event.isKeyboardEvent || event.type == .flagsChanged {
            let phase = event.type == .flagsChanged ? (event.isKeyDown ? "down" : "up") : nil
            details = .key(code: event.keyCode, phase: phase)
        } else {
            return nil
        }
        time = CACurrentMediaTime()
        name = event.eventTypeName
        modifiers = event.modifierString
        flags = event.flags.rawValue
    }

    func logLine(since start: CFTimeInterval) -> String {
        let prefix = String(format: "%8.3f s  ", time - start) + name
        let suffix = "mods:[\(modifiers.isEmpty ? "none" : modifiers)] flags:0x\(String(flags, radix: 16))"
        switch details {
        case .mouse(let button, let x, let y, let userData):
            return "\(prefix) button: \(button) delta:(\(x),\(y)) \(suffix) userData: \(userData)"
        case .key(let code, let phase):
            let key = KeyCode.keyMap[code] ?? "Key(\(code))"
            let keyDetails = phase.map { "phase: \($0)" } ?? "keyCode: \(code)"
            return "\(prefix) key: \(key) \(keyDetails) \(suffix)"
        }
    }
}
