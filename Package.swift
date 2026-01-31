// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CCPlanView",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/Saqoosha/CCHookInstaller", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CCPlanView",
            dependencies: ["CCHookInstaller"],
            path: "Sources/CCPlanView",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
