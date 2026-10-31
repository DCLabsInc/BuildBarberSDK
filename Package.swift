// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestJuiceSDK",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "TestJuiceSDK", targets: ["TestJuiceSDK"])
    ],
    dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.5.0")
    ],
    targets: [
        .target(
            name: "TestJuiceSDK",
            dependencies: [
                .product(name: "ZipArchive", package: "ZipArchive")
            ],
            resources: [.process("Resources")]),
        .testTarget(name: "TestJuiceSDKTests", dependencies: ["TestJuiceSDK"])
    ]
)
