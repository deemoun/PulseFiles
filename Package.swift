// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PulseFiles",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PulseFiles", targets: ["PulseFiles"])],
    targets: [
        .target(name: "PulseFilesUtilities", path: "PulseFiles/Utilities"),
        .target(name: "PulseFilesModels", dependencies: ["PulseFilesUtilities"], path: "PulseFiles/Models"),
        .target(name: "PulseFilesServices", dependencies: ["PulseFilesModels", "PulseFilesUtilities"], path: "PulseFiles/Services"),
        .target(name: "PulseFilesWorkflows", dependencies: ["PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFiles/Commands"),
        .executableTarget(
            name: "PulseFiles",
            dependencies: ["PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles",
            exclude: ["Info.plist", "Utilities", "Models", "Services", "Commands"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "PulseFilesCoreTests", dependencies: ["PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesCoreTests"),
        .testTarget(name: "PulseFilesServicesTests", dependencies: ["PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesServicesTests"),
        .testTarget(name: "PulseFilesTests", dependencies: ["PulseFiles", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesTests", exclude: ["TestSupport/README.md"]),
        .testTarget(name: "PulseFilesAppKitUITests", dependencies: ["PulseFiles", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesAppKitUITests", exclude: ["README.md"])
    ]
)
