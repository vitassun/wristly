// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WristlyCore",
    products: [.library(name: "WristlyCore", targets: ["WristlyCore"])],
    targets: [
        .target(name: "WristlyCore", path: "WatchApp/Models"),
        .testTarget(name: "WristlyCoreTests", dependencies: ["WristlyCore"], path: "Tests/WristlyCoreTests")
    ]
)
