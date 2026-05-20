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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.0.2-rc/LiveBuySDK.xcframework.zip",
            checksum: "64d80c9e4e794de32f523943d9fc69b6f864934085a856e8ba37b5fa6b53e904"
        )
    ]
)
