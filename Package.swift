// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "AstroViewingConditions",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "AstroViewingConditions",
            targets: ["AstroViewingConditions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nikolajjensen/SunCalc.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AstroViewingConditions",
            dependencies: [
                .product(name: "SunCalc", package: "SunCalc"),
            ]
        ),
    ]
)
