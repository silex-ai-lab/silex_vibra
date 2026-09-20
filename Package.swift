// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "vibra",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibraCore", targets: ["VibraCore"]),
        .executable(name: "VibraApp", targets: ["VibraApp"]),
    ],
    targets: [
        .target(name: "VibraCore"),
        .executableTarget(name: "VibraApp", dependencies: ["VibraCore"]),
        .testTarget(
            name: "VibraCoreTests",
            dependencies: ["VibraCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
