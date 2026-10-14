// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingingWorkspace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SongCore", targets: ["SongCore"]),
        .library(name: "SongServices", targets: ["SongServices"]),
        .library(name: "SongPrint", targets: ["SongPrint"]),
        .library(name: "SongNotation", targets: ["SongNotation"]),
        .executable(name: "SongStaffTool", targets: ["SongStaffTool"]),
        .executable(name: "SongSampleTool", targets: ["SongSampleTool"]),
        .executable(name: "SongGenerateTool", targets: ["SongGenerateTool"]),
        .executable(name: "SongPrintTool", targets: ["SongPrintTool"]),
        .executable(name: "SingingWorkspace", targets: ["SingingWorkspace"])
    ],
    targets: [
        .target(name: "SongCore", resources: [.copy("Resources/CMUDict")]),
        .target(name: "SongServices", dependencies: ["SongCore"]),
        .target(name: "SongPrint", dependencies: ["SongCore"]),
        .target(name: "SongNotation", dependencies: ["SongCore"]),
        .executableTarget(name: "SongStaffTool", dependencies: ["SongCore", "SongNotation"]),
        .executableTarget(name: "SongSampleTool", dependencies: ["SongCore"]),
        .executableTarget(name: "SongGenerateTool", dependencies: ["SongCore", "SongServices"]),
        .executableTarget(name: "SongPrintTool", dependencies: ["SongCore", "SongPrint"]),
        .executableTarget(name: "SingingWorkspace", dependencies: ["SongCore", "SongServices", "SongPrint", "SongNotation"]),
        .testTarget(name: "SongCoreTests", dependencies: ["SongCore"]),
        .testTarget(name: "SongPrintTests", dependencies: ["SongCore", "SongPrint"]),
        .testTarget(name: "SongServicesTests", dependencies: ["SongServices"]),
        .testTarget(name: "SongNotationTests", dependencies: ["SongCore", "SongNotation"])
    ]
)
