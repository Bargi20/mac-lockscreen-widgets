// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Bacheca",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Bacheca",
            path: "Sources/Bacheca"
        )
    ],
    swiftLanguageModes: [.v5]
)
