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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.1.7-rc/LiveBuySDK.xcframework.zip",
            checksum: "0e93f9613bcda84b0a00530dbe3bf2c184ae70f2ffea5068a14a68738fa9e53c"
        )
    ]
)
