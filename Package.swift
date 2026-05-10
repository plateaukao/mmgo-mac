// swift-tools-version:5.9
import PackageDescription
import Foundation

// Path to the mmgo build directory containing libmmgo.dylib + libmmgo.h.
// Override with MMGO_BUILD_DIR env var if your layout differs.
let mmgoBuildDir = ProcessInfo.processInfo.environment["MMGO_BUILD_DIR"]
    ?? "/Users/maoyuankao/src/mmgo/build"

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
