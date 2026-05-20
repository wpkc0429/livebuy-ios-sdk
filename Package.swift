// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveBuySDK",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "LiveBuySDK", targets: ["LiveBuySDK"])
    ],
    targets: [
        .binaryTarget(
            name: "LiveBuySDK",
            // Updated automatically by CI on each release.
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.1.8-rc/LiveBuySDK.xcframework.zip",
            checksum: "7b1bda33ac0cf71a66d945119debff31b1047beeed84bb69cad3fbf6ea2ddc18"
        )
    ]
)
