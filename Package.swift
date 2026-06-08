// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Altty",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Altty", targets: ["Altty"]),
    ],
    targets: [
        .executableTarget(
            name: "Altty",
            path: "Sources/Altty",
            swiftSettings: [
                .define("SPM_BUILD"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
