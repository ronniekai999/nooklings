// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nooklings",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Nooklings", targets: ["Byte"])],
    targets: [
        .executableTarget(
            name: "Byte",
            path: "Sources/Byte",
            resources: [.copy("Resources/Companions")]
        ),
        .testTarget(name: "ByteTests", dependencies: ["Byte"])
    ]
)
