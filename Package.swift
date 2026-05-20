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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.2.0-rc/LiveBuySDK.xcframework.zip",
            checksum: "263da048c1f4904da5e49613456f9aeccfc88276bedebeb6ea2caba7faa52e95"
        )
    ]
)
