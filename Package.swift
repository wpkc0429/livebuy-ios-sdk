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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v1.0.0/LiveBuySDK.xcframework.zip",
            checksum: "eec3ee1a3dde88e2c1ddf9ac1dadf47a19135a285f491614f05c4367678e71a2"
        )
    ]
)
