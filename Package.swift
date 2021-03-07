// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "pix-batch-crop",
    platforms: [
        .macOS(.v10_14),
    ],
    dependencies: [
        .package(url: "https://github.com/heestand-xyz/PixelKit", from: "1.2.3"),
    ],
    targets: [
        .target(name: "pix-batch-crop", dependencies: ["PixelKit"]),
    ]
)
