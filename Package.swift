// swift-tools-version: 6.0

import PackageDescription
import Foundation

let developerFrameworks = [
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"].map { "\($0)/Library/Developer/Frameworks" },
    "/Applications/Xcode.app/Contents/Developer/Library/Developer/Frameworks",
    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
].compactMap { $0 }.first { FileManager.default.fileExists(atPath: "\($0)/Testing.framework") }!

let package = Package(
    name: "Altty",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "Altty", targets: ["Altty"]),
    ],
    targets: [
        .executableTarget(
            name: "Altty",
            path: "Sources/Altty"
        ),
        .testTarget(
            name: "AlttyTests",
            dependencies: ["Altty"],
            swiftSettings: [.unsafeFlags(["-F", developerFrameworks])],
            linkerSettings: [.unsafeFlags([
                "-F", developerFrameworks,
                "-Xlinker", "-rpath", "-Xlinker", developerFrameworks,
            ])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
