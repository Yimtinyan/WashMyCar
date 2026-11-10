// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WashCore",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "WashCore", targets: ["WashCore"])],
    targets: [
        .target(name: "WashCore", path: "Shared"),
        .testTarget(name: "WashCoreTests", dependencies: ["WashCore"], path: "Tests", resources: [.copy("Fixtures")])
    ]
)
