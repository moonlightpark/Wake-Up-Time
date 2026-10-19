// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WakeUpTime",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WakeUpTime",
            path: "Sources/WakeUpTime",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
