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
        .target(name: "PulseFilesCapabilities", dependencies: ["PulseFilesModels"], path: "PulseFiles/Capabilities"),
        .target(name: "PulseFilesServices", dependencies: ["PulseFilesCapabilities", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFiles/Services"),
        .target(name: "PulseFilesWorkflows", dependencies: ["PulseFilesModels", "PulseFilesUtilities"], path: "PulseFiles/Commands"),
        .target(
            name: "PulseFilesPresentationSupport",
            dependencies: ["PulseFilesCapabilities", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles/PresentationSupport",
            exclude: ["Commands"]
        ),
        .target(
            name: "PulseFilesPresentationCommands",
            dependencies: ["PulseFilesPresentationSupport", "PulseFilesWorkflows"],
            path: "PulseFiles/PresentationSupport/Commands"
        ),
        .target(
            name: "PulseFilesTerminal",
            dependencies: ["PulseFilesCapabilities", "PulseFilesPresentationSupport", "PulseFilesUtilities"],
            path: "PulseFiles/Terminal"
        ),
        .target(
            name: "PulseFilesPane",
            dependencies: ["PulseFilesCapabilities", "PulseFilesPresentationSupport", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles/FilePane"
        ),
        .target(
            name: "PulseFilesSidebar",
            dependencies: ["PulseFilesCapabilities", "PulseFilesPresentationSupport", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles/Sidebar"
        ),
        .target(
            name: "PulseFilesSettings",
            dependencies: ["PulseFilesCapabilities", "PulseFilesPresentationSupport", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles/Settings"
        ),
        .target(
            name: "PulseFilesAppCoordination",
            dependencies: ["PulseFilesWorkflows", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles/AppCoordination"
        ),
        .executableTarget(
            name: "PulseFiles",
            dependencies: ["PulseFilesAppCoordination", "PulseFilesCapabilities", "PulseFilesPane", "PulseFilesSidebar", "PulseFilesSettings", "PulseFilesTerminal", "PulseFilesPresentationCommands", "PulseFilesPresentationSupport", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"],
            path: "PulseFiles",
            exclude: ["Info.plist", "AppCoordination", "Capabilities", "Utilities", "Models", "Services", "Commands", "FilePane", "Sidebar", "Settings", "Terminal", "PresentationSupport/Commands", "PresentationSupport/Models", "PresentationSupport/Module", "PresentationSupport/Services", "PresentationSupport/Utilities"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "PulseFilesCoreTests", dependencies: ["PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesCoreTests"),
        .testTarget(name: "PulseFilesWorkflowsTests", dependencies: ["PulseFilesWorkflows", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesWorkflowsTests"),
        .testTarget(name: "PulseFilesServicesTests", dependencies: ["PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesServicesTests"),
        .testTarget(name: "PulseFilesTests", dependencies: ["PulseFilesCapabilities", "PulseFiles", "PulseFilesAppCoordination", "PulseFilesPane", "PulseFilesSidebar", "PulseFilesSettings", "PulseFilesTerminal", "PulseFilesPresentationCommands", "PulseFilesPresentationSupport", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesTests", exclude: ["TestSupport/README.md"]),
        .testTarget(name: "PulseFilesAppKitUITests", dependencies: ["PulseFiles", "PulseFilesPane", "PulseFilesSidebar", "PulseFilesSettings", "PulseFilesPresentationSupport", "PulseFilesWorkflows", "PulseFilesServices", "PulseFilesModels", "PulseFilesUtilities"], path: "PulseFilesAppKitUITests", exclude: ["README.md"])
    ]
)
