// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PulseFiles",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PulseFiles", targets: ["PulseFiles"])
    ],
    targets: [
        .executableTarget(
            name: "PulseFiles",
            path: "PulseFiles",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PulseFilesTests",
            dependencies: ["PulseFiles"],
            path: "PulseFilesTests"
        )
    ]
)
