// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarkdownViewer",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "MarkdownViewer",
            path: "Sources/MarkdownViewer",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
