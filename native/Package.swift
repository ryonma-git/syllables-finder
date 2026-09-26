// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingingWorkspace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SongCore", targets: ["SongCore"]),
        .library(name: "SongServices", targets: ["SongServices"]),
        .executable(name: "SongSampleTool", targets: ["SongSampleTool"]),
        .executable(name: "SingingWorkspace", targets: ["SingingWorkspace"])
    ],
    targets: [
        .target(name: "SongCore"),
        .target(name: "SongServices", dependencies: ["SongCore"]),
        .executableTarget(name: "SongSampleTool", dependencies: ["SongCore"]),
        .executableTarget(name: "SingingWorkspace", dependencies: ["SongCore", "SongServices"]),
        .testTarget(name: "SongCoreTests", dependencies: ["SongCore"]),
        .testTarget(name: "SongServicesTests", dependencies: ["SongServices"])
    ]
)
