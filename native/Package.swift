// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingingWorkspace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SongCore", targets: ["SongCore"]),
        .library(name: "SongServices", targets: ["SongServices"]),
        .library(name: "SongPrint", targets: ["SongPrint"]),
        .executable(name: "SongSampleTool", targets: ["SongSampleTool"]),
        .executable(name: "SongPrintTool", targets: ["SongPrintTool"]),
        .executable(name: "SingingWorkspace", targets: ["SingingWorkspace"])
    ],
    targets: [
        .target(name: "SongCore"),
        .target(name: "SongServices", dependencies: ["SongCore"]),
        .target(name: "SongPrint", dependencies: ["SongCore"]),
        .executableTarget(name: "SongSampleTool", dependencies: ["SongCore"]),
        .executableTarget(name: "SongPrintTool", dependencies: ["SongCore", "SongPrint"]),
        .executableTarget(name: "SingingWorkspace", dependencies: ["SongCore", "SongServices", "SongPrint"]),
        .testTarget(name: "SongCoreTests", dependencies: ["SongCore"]),
        .testTarget(name: "SongPrintTests", dependencies: ["SongCore", "SongPrint"]),
        .testTarget(name: "SongServicesTests", dependencies: ["SongServices"])
    ]
)
