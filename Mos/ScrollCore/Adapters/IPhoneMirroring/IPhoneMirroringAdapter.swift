import Cocoa

final class IPhoneMirroringAdapter: PhasedWindowScrollAdapter {
    static let descriptor = ScrollAdapterDescriptor(
        identifier: "iphone-mirroring",
        bundleIdentifiers: ["com.apple.ScreenContinuity"],
        minimumSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
    )

    init() {
        super.init(descriptor: Self.descriptor)
    }
}
