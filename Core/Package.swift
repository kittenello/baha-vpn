// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BahaCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "BahaCore", targets: ["BahaCore"])],
    targets: [
        .target(name: "BahaCore"),
        .testTarget(name: "BahaCoreTests", dependencies: ["BahaCore"])
    ]
)
