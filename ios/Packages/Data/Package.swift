// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Data",
    platforms: [.iOS("15.6"), .macOS(.v14)],
    products: [.library(name: "Data", targets: ["Data"])],
    dependencies: [.package(path: "../Domain")],
    targets: [
        .target(name: "Data", dependencies: ["Domain"]),
        .testTarget(name: "DataTests", dependencies: ["Data", "Domain"]),
        .testTarget(name: "DataIntegrationTests", dependencies: ["Data"]),
    ]
)
