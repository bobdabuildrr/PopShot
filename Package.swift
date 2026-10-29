// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PopShot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PopShot",
            path: "Sources/PopShot"
        )
    ]
)
