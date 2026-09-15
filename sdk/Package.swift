// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FaceKeyKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FaceKeyKit", targets: ["FaceKeyKit"])],
    targets: [
        .target(name: "FaceKeyKit"),
        .testTarget(name: "FaceKeyKitTests", dependencies: ["FaceKeyKit"]),
    ]
)
