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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.1.9-rc/LiveBuySDK.xcframework.zip",
            checksum: "4cc4b16c54f432d20685e52f636e5594c686662dd0d1b7fa7ba521c6d71edd0c"
        )
    ]
)
