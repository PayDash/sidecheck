// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sidecheck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sidecheck",
            path: "Sources/Sidecheck"
        ),
        .testTarget(
            name: "SidecheckTests",
            dependencies: ["Sidecheck"],
            path: "Tests/SidecheckTests"
        )
    ]
)
