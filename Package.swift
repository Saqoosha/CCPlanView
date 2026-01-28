// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CCPlanView",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "CCPlanView",
            path: "Sources/CCPlanView",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
