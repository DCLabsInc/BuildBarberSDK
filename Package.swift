// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestJuiceSDK",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "TestJuiceSDK", targets: ["TestJuiceSDK"])
    ],
    targets: [
        .target(
            name: "TestJuiceSDK",
            resources: [.process("Resources")]),
        .testTarget(name: "TestJuiceSDKTests", dependencies: ["TestJuiceSDK"])
    ]
)
