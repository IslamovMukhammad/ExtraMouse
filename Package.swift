// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExtraMouse",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "ExtraMouse",
            path: "Sources/ExtraMouse"
        ),
        .testTarget(
            name: "ExtraMouseTests",
            dependencies: ["ExtraMouse"],
            path: "Tests/ExtraMouseTests"
        ),
    ]
)
