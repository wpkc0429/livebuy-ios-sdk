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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v1.2.0-rc.2/LiveBuySDK.xcframework.zip",
            checksum: "e29a9e03a66e1175beaf17d09476341ff51043096645b0fdca482420559aece2"
        )
    ]
)
