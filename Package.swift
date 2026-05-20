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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v1.1.0/LiveBuySDK.xcframework.zip",
            checksum: "cf11586d19699fadd5dff281292bfe4afac9f72dd6e1f06e2987244d35943ca8"
        )
    ]
)
