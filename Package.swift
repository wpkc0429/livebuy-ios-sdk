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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.2.2-rc/LiveBuySDK.xcframework.zip",
            checksum: "d8bae6266617f353d3ef1c4acc39ccd0079393c4ecb07342f2b3c8457f6c3ad3"
        )
    ]
)
