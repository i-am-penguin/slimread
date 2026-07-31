// swift-tools-version: 5.9

// This manifest only resolves inside Swift Playgrounds / Xcode, which provide
// the AppleProductTypes module. Open SlimRead.swiftpm with Swift Playgrounds
// on an iPad, then use "Run on device" to install onto your iPhone.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "SlimRead",
    platforms: [.iOS("16.0")],
    products: [
        .iOSApplication(
            name: "SlimRead",
            targets: ["SlimRead"],
            bundleIdentifier: "com.example.slimread",
            displayVersion: "1.0",
            bundleVersion: "1",
            supportedDeviceFamilies: [.phone, .pad],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft
            ],
            additionalInfoPlistContentFilePath: "Info.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "SlimRead",
            path: "Sources"
        )
    ]
)
