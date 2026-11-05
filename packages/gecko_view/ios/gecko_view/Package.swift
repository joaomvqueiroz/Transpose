// swift-tools-version: 5.9
import PackageDescription

// The plugin never links Gecko. TransponoGecko.framework (built in CI against
// the Gecko engine kit) is loaded at process start by Runner's entry point;
// this plugin finds its bridge class at run time and stays a no-op otherwise.
let package = Package(
    name: "gecko_view",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "gecko-view", targets: ["gecko_view"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "gecko_view",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
