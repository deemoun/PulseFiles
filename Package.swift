// swift-tools-version: 5.9
// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

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
        .target(
            name: "PulseFilesPresentationSupport",
            dependencies: ["PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles/PresentationSupport",
            exclude: ["Commands"]
        ),
        .target(
            name: "PulseFilesTerminal",
            dependencies: ["PulseFilesPresentationSupport", "PulseFilesServices", "PulseFilesUtilities"],
            path: "PulseFiles/Terminal"
        ),
        .target(
            name: "PulseFilesPane",
            dependencies: ["PulseFilesPresentationSupport", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles/FilePane"
        ),
        .target(
            name: "PulseFilesSidebar",
            dependencies: ["PulseFilesPresentationSupport", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles/Sidebar"
        ),
        .target(
            name: "PulseFilesSettings",
            dependencies: ["PulseFilesPresentationSupport", "PulseFilesServices", "PulseFilesModels"],
            path: "PulseFiles/Settings"
        ),
        .executableTarget(
            name: "PulseFiles",
            dependencies: ["PulseFilesPane", "PulseFilesSidebar", "PulseFilesSettings", "PulseFilesTerminal", "PulseFilesPresentationSupport", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles",
            exclude: ["Info.plist", "Utilities", "Models", "Services", "Commands", "FilePane", "Sidebar", "Settings", "Terminal", "PresentationSupport/Models", "PresentationSupport/Module", "PresentationSupport/Services", "PresentationSupport/Utilities"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "PulseFilesCoreTests", dependencies: ["PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesCoreTests"),
        .testTarget(name: "PulseFilesServicesTests", dependencies: ["PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesServicesTests"),
        .testTarget(name: "PulseFilesTests", dependencies: ["PulseFiles", "PulseFilesPane", "PulseFilesSidebar", "PulseFilesSettings", "PulseFilesTerminal", "PulseFilesPresentationSupport", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesTests", exclude: ["TestSupport/README.md"]),
        .testTarget(name: "PulseFilesAppKitUITests", dependencies: ["PulseFiles", "PulseFilesPane", "PulseFilesSidebar", "PulseFilesSettings", "PulseFilesPresentationSupport", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesAppKitUITests", exclude: ["README.md"])
    ]
)
