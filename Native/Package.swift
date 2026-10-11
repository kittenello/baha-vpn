// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "XrayNative", platforms: [.iOS(.v17)],
    products: [.library(name: "XrayNative", targets: ["XrayNative"])],
    targets: [.binaryTarget(name: "XrayNative", path: "XrayNative.xcframework")])
