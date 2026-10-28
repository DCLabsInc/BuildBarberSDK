// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuildBarberSDK",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "BuildBarberSDK", targets: ["BuildBarberSDK"])
    ],
    targets: [
        .target(name: "BuildBarberSDK", resources: [.process("Resources")]),
        .testTarget(name: "BuildBarberSDKTests", dependencies: ["BuildBarberSDK"])
    ]
)
