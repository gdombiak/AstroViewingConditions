// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AstroEngine",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
    ],
    products: [
        .library(name: "AstroEngine", targets: ["AstroEngine"]),
        .executable(name: "astro-engine-eval", targets: ["AstroEngineEval"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nikolajjensen/SunCalc.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AstroEngine",
            dependencies: [
                .product(name: "SunCalc", package: "SunCalc"),
            ],
            resources: [
                .copy("Resources/data"),
            ]
        ),
        .executableTarget(
            name: "AstroEngineEval",
            dependencies: ["AstroEngine"]
        ),
        .testTarget(
            name: "AstroEngineTests",
            dependencies: ["AstroEngine"]
        ),
    ]
)
