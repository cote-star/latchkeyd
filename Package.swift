// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "latchkeyd",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LatchkeydCore", targets: ["LatchkeydCore"]),
        .executable(name: "latchkeyd", targets: ["LatchkeydCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", exact: "6.2.4")
    ],
    targets: [
        .target(
            name: "LatchkeydCore"
        ),
        .executableTarget(
            name: "LatchkeydCLI",
            dependencies: ["LatchkeydCore"]
        ),
        .testTarget(
            name: "LatchkeydTests",
            dependencies: [
                "LatchkeydCore",
                "LatchkeydCLI",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
