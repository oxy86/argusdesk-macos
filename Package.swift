// swift-tools-version: 6.0

import PackageDescription

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
            path: "Sources/ArgusDesk",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(name: "ArgusDeskTests", dependencies: ["ArgusDesk"])
    ]
)
