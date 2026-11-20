// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TapeKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TapeCore", targets: ["TapeCore"]),
        .library(name: "TapeMac", targets: ["TapeMac"]),
    ],
    targets: [
        .target(name: "TapeCore"),
        .target(name: "TapeMac", dependencies: ["TapeCore"]),
        .testTarget(name: "TapeCoreTests", dependencies: ["TapeCore"]),
    ]
)
