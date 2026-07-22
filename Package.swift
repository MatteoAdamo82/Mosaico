// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mosaico",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CAXShim",
            path: "Sources/CAXShim"
        ),
        .executableTarget(
            name: "Mosaico",
            dependencies: ["CAXShim"],
            path: "Sources/Mosaico"
        ),
    ]
)
