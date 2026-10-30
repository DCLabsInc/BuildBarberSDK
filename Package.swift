// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuildBarberSDK",
    platforms: [.iOS("18.0")],
    dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.5.0")
    ],
    products: [
        .library(name: "BuildBarberSDK", targets: ["BuildBarberSDK"])
    ],
    targets: [
        .target(
            name: "BuildBarberSDK",
            dependencies: [
                .product(name: "ZipArchive", package: "ZipArchive", condition: .when(platforms: [.iOS]))
            ],
            resources: [.process("Resources")]),
        .testTarget(name: "BuildBarberSDKTests", dependencies: ["BuildBarberSDK"])
    ]
)
