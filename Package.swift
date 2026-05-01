// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MayarMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MayarMenuBar",
            path: "Sources/MayarMenuBar"
        )
    ]
)
