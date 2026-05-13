// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MmgoMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MmgoMac",
            resources: [
                .copy("Resources/mermaid.min.js"),
                .copy("Resources/mermaid.html"),
            ]
        ),
    ]
)
