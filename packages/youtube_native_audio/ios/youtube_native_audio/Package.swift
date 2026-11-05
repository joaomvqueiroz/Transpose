// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "youtube_native_audio",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "youtube-native-audio", targets: ["youtube_native_audio"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/alexeichhorn/YouTubeKit", .upToNextMinor(from: "0.4.10")),
    ],
    targets: [
        .target(
            name: "youtube_native_audio",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "YouTubeKit", package: "YouTubeKit"),
            ]
        )
    ]
)
