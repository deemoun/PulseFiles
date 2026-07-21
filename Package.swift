// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PulseFiles",
    defaultLocalization: "en",
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
            path: "PulseFilesTests",
            exclude: ["TestSupport/README.md"]
        ),
        // SwiftPM cannot create an Xcode UI-test bundle.  Keep AppKit wiring
        // coverage separate from service tests while still exercising the
        // actual views and accessibility tree in-process.
        .testTarget(
            name: "PulseFilesAppKitUITests",
            dependencies: ["PulseFiles"],
            path: "PulseFilesAppKitUITests",
            exclude: ["README.md"]
        )
    ]
)
