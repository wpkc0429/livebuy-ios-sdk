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
            url: "https://github.com/wpkc0429/livebuy-ios-sdk/releases/download/v0.0.5-rc/LiveBuySDK.xcframework.zip",
            checksum: "4d2b004ec2188eeae22f2eeb629b2b10e43d7f41ea94c3be61391f461c5f91ea"
        )
    ]
)
