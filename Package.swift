// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StarTrailsApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StarTrailsApp", targets: ["StarTrailsApp"])
    ],
    targets: [
        .executableTarget(
            name: "StarTrailsApp",
            dependencies: [],
            path: "Sources/StarTrailsApp",
            resources: [
                .copy("Resources/streaks.mlpackage"),
                .copy("Resources/gapfill.mlpackage")
            ]
        ),
    ]
)
