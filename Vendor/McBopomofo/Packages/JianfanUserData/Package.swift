// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JianfanUserData",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "JianfanUserData", targets: ["JianfanUserData"])],
    targets: [
        .target(name: "JianfanUserData", resources: [.process("Resources")]),
        .testTarget(name: "JianfanUserDataTests", dependencies: ["JianfanUserData"]),
    ]
)
