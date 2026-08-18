// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "advanced_haptics",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "advanced-haptics", targets: ["advanced_haptics"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "advanced_haptics",
            dependencies: []
        )
    ]
)
