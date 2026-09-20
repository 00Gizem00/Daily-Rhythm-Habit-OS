// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DailyRhythmCore",
    platforms: [.iOS(.v18), .macOS(.v13)],
    products: [.library(name: "DailyRhythmCore", targets: ["DailyRhythmCore"])],
    targets: [
        .target(name: "DailyRhythmCore"),
        .testTarget(name: "DailyRhythmCoreTests", dependencies: ["DailyRhythmCore"], resources: [.copy("Fixtures")])
    ]
)
