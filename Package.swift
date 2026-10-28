// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BiliWidget", platforms: [.macOS(.v14)], products: [
    .executable(name: "BiliWidget", targets: ["BiliWidget"]),
    .library(name: "TrackerCore", targets: ["TrackerCore"])
], targets: [
    .target(name: "TrackerCore"),
    .executableTarget(name: "BiliWidget", dependencies: ["TrackerCore"]),
    .executableTarget(name: "TrackerChecks", dependencies: ["TrackerCore"], path: "Tests/TrackerCoreTests")
])
