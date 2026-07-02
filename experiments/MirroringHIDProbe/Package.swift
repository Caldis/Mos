// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MirroringHIDProbe",
    platforms: [.macOS("15.0")],   // CoreHID.HIDVirtualDevice 自 macOS 15 起可用
    targets: [
        .executableTarget(
            name: "MirroringHIDProbe",
            path: "Sources/MirroringHIDProbe"
        )
    ]
)
