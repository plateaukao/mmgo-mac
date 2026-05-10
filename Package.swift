// swift-tools-version:5.9
import PackageDescription
import Foundation

// Path to the directory containing libmmgo.dylib. Defaults to the bundled
// `Frameworks/` directory next to this Package.swift so the repo is
// self-contained. Override with MMGO_BUILD_DIR to point at a fresher build
// (e.g. a sibling mmgo checkout).
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let mmgoBuildDir = ProcessInfo.processInfo.environment["MMGO_BUILD_DIR"]
    ?? "\(packageDir)/Frameworks"

let package = Package(
    name: "MmgoMac",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CMmgo",
            path: "Sources/CMmgo"
        ),
        .executableTarget(
            name: "MmgoMac",
            dependencies: ["CMmgo"],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(mmgoBuildDir)",
                    "-lmmgo",
                    "-Xlinker", "-rpath",
                    "-Xlinker", mmgoBuildDir,
                ]),
            ]
        ),
    ]
)
