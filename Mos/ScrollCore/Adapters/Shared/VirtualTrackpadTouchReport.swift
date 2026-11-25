import Foundation

enum VirtualTrackpadTouchReport {
    private static let width = 8134
    private static let height = 5206
    private static let fingerX = [3400, 4700]

    struct Position: Sendable {
        let xOffset: Int
        let y: Int

        init(xOffset: Int = 0, y: Int) {
            self.xOffset = min(max(xOffset, 300 - fingerX[0]), width - 300 - fingerX[1])
            self.y = min(max(y, 0), height)
        }
    }

    enum Phase: UInt32 {
        case began = 3
        case moved = 4
        case stopped = 7
        case inactive = 0
    }

    private struct Contact {
        let x: Int
        let y: Int
        let phase: Phase
        let finger: UInt32
        let id: UInt8
    }

    static func contactReport(at position: Position, firstID: UInt8, phase: Phase, milliseconds: UInt32) -> Data {
        let touching = phase == .began || phase == .moved
        let contacts = [
            Contact(x: fingerX[0] + position.xOffset, y: position.y, phase: phase, finger: 2, id: firstID),
            Contact(x: fingerX[1] + position.xOffset, y: position.y, phase: phase, finger: 3, id: firstID % 15 + 1),
        ]
        return encode(contacts, touching: touching, milliseconds: milliseconds)
    }

    static func releaseReports(at position: Position, firstID: UInt8, milliseconds: UInt32) -> [Data] {
        // The Magic Trackpad 2 driver expects stopped contacts, one inactive contact, then an empty frame.
        let inactive = Contact(
            x: fingerX[0] + position.xOffset, y: position.y, phase: .inactive, finger: 0, id: firstID
        )
        return [
            contactReport(at: position, firstID: firstID, phase: .stopped, milliseconds: milliseconds),
            encode([inactive], touching: false, milliseconds: milliseconds),
            encode([], touching: false, milliseconds: milliseconds),
        ]
    }

    private static func encode(_ contacts: [Contact], touching: Bool, milliseconds: UInt32) -> Data {
        let timestamp = (milliseconds << 3) | 0x4
        var bytes: [UInt8] = [
            0x02, 0, 0, 0, 0, 0, 0, touching ? 0x03 : 0x02, 0x31,
            UInt8(truncatingIfNeeded: timestamp),
            UInt8(truncatingIfNeeded: timestamp >> 8),
            UInt8(truncatingIfNeeded: timestamp >> 16),
        ]
        bytes.reserveCapacity(12 + contacts.count * 9)
        for contact in contacts {
            let x = UInt32(truncatingIfNeeded: contact.x - width / 2) & 0x1fff
            let y = UInt32(truncatingIfNeeded: height / 2 - contact.y) & 0x1fff
            let packed = x | (y << 13) | (contact.finger << 26) | (contact.phase.rawValue << 29)
            let active: UInt8 = contact.phase == .began || contact.phase == .moved ? 1 : 0
            bytes += [
                UInt8(truncatingIfNeeded: packed),
                UInt8(truncatingIfNeeded: packed >> 8),
                UInt8(truncatingIfNeeded: packed >> 16),
                UInt8(truncatingIfNeeded: packed >> 24),
                20 * active, 20 * active, 10 * active, 5 * active,
                (contact.id & 0x0f) | 0x80,
            ]
        }
        return Data(bytes)
    }
}
