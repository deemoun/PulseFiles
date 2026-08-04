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
        .target(
            name: "PulseFilesUtilities",
            path: "PulseFiles/Utilities",
            exclude: [
                "AccessibilityIdentifiers.swift",
                "FileIconProvider.swift",
                "FileTypeColorPalette.swift",
                "LiquidGlassStyle.swift"
            ],
            sources: [
                "DateFormatter+PulseFiles.swift",
                "ExperimentalFlags.swift",
                "FileNameValidator.swift",
                "FilePathComparison.swift",
                "FileSizeFormatter.swift",
                "Localization.swift",
                "PathUtilities.swift"
            ]
        ),
        .target(
            name: "PulseFilesModels",
            dependencies: ["PulseFilesUtilities"],
            path: "PulseFiles/Models",
            exclude: ["QuickLocation.swift"]
        ),
        .executableTarget(
            name: "PulseFiles",
            dependencies: ["PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles",
            exclude: [
                "Info.plist",
                "Models/Bookmark.swift",
                "Models/FileItem.swift",
                "Models/FileOperation.swift",
                "Models/FileOperationResult.swift",
                "Models/FilePatternMatcher.swift",
                "Models/NavigationHistory.swift",
                "Models/PanePresentationMode.swift",
                "Models/PaneState.swift",
                "Models/QuickSearch.swift",
                "Models/VolumeStatusPresentation.swift",
                "Models/VolumeStatusResolutionCache.swift",
                "Utilities/AccessibilityIdentifiers.swift",
                "Utilities/DateFormatter+PulseFiles.swift",
                "Utilities/ExperimentalFlags.swift",
                "Utilities/FileNameValidator.swift",
                "Utilities/FilePathComparison.swift",
                "Utilities/FileSizeFormatter.swift",
                "Utilities/Localization.swift",
                "Utilities/PathUtilities.swift"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PulseFilesTests",
            dependencies: ["PulseFiles", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFilesTests",
            exclude: ["TestSupport/README.md"]
        ),
        // SwiftPM cannot create an Xcode UI-test bundle.  Keep AppKit wiring
        // coverage separate from service tests while still exercising the
        // actual views and accessibility tree in-process.
        .testTarget(
            name: "PulseFilesAppKitUITests",
            dependencies: ["PulseFiles", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFilesAppKitUITests",
            exclude: ["README.md"]
        )
    ]
)
