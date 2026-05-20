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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.0.9-rc/LiveBuySDK.xcframework.zip",
            checksum: "cc5b67ee89d0e45014387bc919d5e144f6b39103f5298ce1a25d8040cb1b971c"
        )
    ]
)
