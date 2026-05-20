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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.1.6-rc/LiveBuySDK.xcframework.zip",
            checksum: "57ef17321abfef5cb1cfc218dd7d38fc333efa23e3865f038bb55ac961e74a2b"
        )
    ]
)
