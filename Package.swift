// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Megabyte",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Megabyte", path: "Sources/Megabyte"),
    ]
)
