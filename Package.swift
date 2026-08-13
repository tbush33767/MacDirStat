// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MacDirStat",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "MacDirStatCore"),
        .executableTarget(
            name: "MacDirStat",
            dependencies: ["MacDirStatCore"]
        ),
        .executableTarget(
            name: "MacDirStatCLI",
            dependencies: ["MacDirStatCore"]
        ),
        .testTarget(
            name: "MacDirStatCoreTests",
            dependencies: ["MacDirStatCore"]
        ),
    ]
)
