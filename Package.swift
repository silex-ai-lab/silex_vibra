// swift-tools-version:6.0
import PackageDescription
import Foundation

// swift-testing ships inside the Command Line Tools as a framework, but unlike
// a full Xcode install the CLT toolchain does not put it on the default search
// path. Detect that case and add the flags only there, so this package still
// builds unmodified on a machine that has Xcode.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltLib = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let needsCLTTestingFlags = FileManager.default.fileExists(
    atPath: cltFrameworks + "/Testing.framework"
) && !FileManager.default.fileExists(atPath: "/Applications/Xcode.app")

let testSwiftSettings: [SwiftSetting] = needsCLTTestingFlags
    ? [.unsafeFlags(["-F", cltFrameworks])]
    : []
// With Xcode, the compiler finds Testing on its own, but the test runner is an
// executable rather than a .testTarget, so nothing adds Xcode's framework
// directory to its rpath and it fails to launch.
let xcodeDeveloper = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Applications/Xcode.app/Contents/Developer"
let xcodePlatform = xcodeDeveloper + "/Platforms/MacOSX.platform/Developer"
let needsXcodeTestingRpath = !needsCLTTestingFlags && FileManager.default.fileExists(
    atPath: xcodePlatform + "/Library/Frameworks/Testing.framework"
)

let testLinkerSettings: [LinkerSetting] = needsCLTTestingFlags
    ? [.unsafeFlags([
        "-F", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", cltLib,
      ])]
    : needsXcodeTestingRpath
    ? [.unsafeFlags([
        "-Xlinker", "-rpath", "-Xlinker", xcodePlatform + "/Library/Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", xcodePlatform + "/usr/lib",
      ])]
    : []

let package = Package(
    name: "vibra",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibraCore", targets: ["VibraCore"]),
        .executable(name: "VibraApp", targets: ["VibraApp"]),
        .executable(name: "VibraTests", targets: ["VibraTests"]),
    ],
    targets: [
        .target(name: "VibraCore"),
        .executableTarget(name: "VibraApp", dependencies: ["VibraCore"]),
        // Tests live in an executable, not a .testTarget - see
        // Sources/VibraTests/main.swift for why.
        .executableTarget(
            name: "VibraTests",
            dependencies: ["VibraCore", "VibraTestCases"],
            path: "Sources/VibraTests",
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
        .target(
            name: "VibraTestCases",
            dependencies: ["VibraCore"],
            path: "Tests/VibraCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
    ]
)
