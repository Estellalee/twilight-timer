// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "倒计时Timer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "倒计时Timer", targets: ["倒计时Timer"])
    ],
    targets: [
        .executableTarget(name: "倒计时Timer")
    ]
)
