// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DocPreview",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DocPreview",
            resources: [.copy("Resources/ui")]
        )
    ]
)
