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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.0.7-rc/LiveBuySDK.xcframework.zip",
            checksum: "2f24a2db55b717c2dcf7ca1a8394204ea4b801d7f6107d4d874497910fb04a0f"
        )
    ]
)
