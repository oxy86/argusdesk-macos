// swift-tools-version: 6.0

import PackageDescription

/// Swift Package Manager manifest for ArgusDesk for macOS.
///
/// The native macOS implementation intentionally has no third-party
/// dependencies. The executable target links against native Apple
/// frameworks through the source imports.
let package = Package(
    name: "ArgusDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ArgusDesk", targets: ["ArgusDesk"])
    ],
    targets: [
        .executableTarget(
            name: "ArgusDesk",
            path: "Sources/ArgusDesk"
        )
    ]
)
