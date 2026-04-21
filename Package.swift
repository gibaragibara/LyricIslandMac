// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LyricIslandMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "LyricIslandMac", targets: ["LyricIslandMac"]),
    ],
    targets: [
        .executableTarget(
            name: "LyricIslandMac"
        ),
        .testTarget(
            name: "LyricIslandMacTests",
            dependencies: ["LyricIslandMac"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
