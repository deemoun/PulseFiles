import AppKit

final class MainWindowController: NSWindowController {
    static let frameAutosaveName = "PulseFilesMainWindow"

    init(
        settings: SettingsService = SettingsService(),
        accessPolicy: SandboxFileAccessPolicy = .current,
        dependencies: MainWindowDependencies? = nil,
        sandboxRootEnsurer: @escaping () -> Void = ExperimentalFlags.ensureAppSandboxRootExists
    ) {
        let dependencies = dependencies ?? .production(accessPolicy: accessPolicy)
        let content = MainWindowViewController(
            settings: settings,
            accessPolicy: accessPolicy,
            dependencies: dependencies,
            workflowDependencies: .production(from: dependencies, accessPolicy: accessPolicy),
            sandboxRootEnsurer: sandboxRootEnsurer
        )
        let window = NSWindow(contentViewController: content)
        window.title = "PulseFiles"
        let availableFrames = NSScreen.screens.map(\.visibleFrame)
        let fallbackVisibleFrame = NSScreen.main?.visibleFrame
            ?? availableFrames.first
            ?? MainWindowFrameLayout.defaultVisibleFrame
        window.setFrameAutosaveName(Self.frameAutosaveName)
        let restoredFrame = window.setFrameUsingName(Self.frameAutosaveName)
        let requestedFrame = restoredFrame
            ? window.frame
            : MainWindowFrameLayout.fallbackFrame(in: fallbackVisibleFrame)
        window.setFrame(
            MainWindowFrameLayout.clampedFrame(
                requestedFrame,
                availableFrames: availableFrames,
                fallbackVisibleFrame: fallbackVisibleFrame
            ),
            display: false
        )
        window.minSize = NSSize(width: 920, height: 560)
        window.backgroundColor = LiquidGlassStyle.windowBackground
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.toolbar = PulseToolbar(owner: content)
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

/// Keeps the main window reachable after a display is disconnected, resized,
/// or has a different usable area because of menu bar or Dock placement.
enum MainWindowFrameLayout {
    static let defaultFrame = NSRect(x: 120, y: 120, width: 1280, height: 820)
    static let defaultVisibleFrame = NSRect(x: 0, y: 0, width: 1280, height: 820)

    static func fallbackFrame(in visibleFrame: NSRect) -> NSRect {
        let size = NSSize(
            width: min(defaultFrame.width, visibleFrame.width),
            height: min(defaultFrame.height, visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func clampedFrame(
        _ frame: NSRect,
        availableFrames: [NSRect],
        fallbackVisibleFrame: NSRect
    ) -> NSRect {
        let visibleFrame = availableFrames
            .max(by: { intersectionArea(of: frame, with: $0) < intersectionArea(of: frame, with: $1) })
            .flatMap { intersectionArea(of: frame, with: $0) > 0 ? $0 : nil }
            ?? fallbackVisibleFrame
        let size = NSSize(
            width: min(max(frame.width, 1), visibleFrame.width),
            height: min(max(frame.height, 1), visibleFrame.height)
        )
        return NSRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private static func intersectionArea(of frame: NSRect, with visibleFrame: NSRect) -> CGFloat {
        let intersection = frame.intersection(visibleFrame)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

private final class PulseToolbar: NSToolbar {
    init(owner: MainWindowViewController) {
        super.init(identifier: "PulseFilesToolbar")
        delegate = owner
        displayMode = .iconOnly
        allowsUserCustomization = false
    }
}
