// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebLexicon",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../../native")],
    targets: [
        .executableTarget(name: "Lexicon", dependencies: [.product(name: "SongCore", package: "native")])
    ]
)
