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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.0.6-rc/LiveBuySDK.xcframework.zip",
            checksum: "d49f012825b22f5ac4ff39b669650fd20a9ccb06885171f6866486b893fed35c"
        )
    ]
)
