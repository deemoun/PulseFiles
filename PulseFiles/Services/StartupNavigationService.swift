import Foundation
import PulseFilesModels
import PulseFilesUtilities

package enum StartupDirectorySource: Equatable { case `default`, lastVisited, userSelected }

package struct StartupDirectoryResolution {
    package let directory: URL
    package let requestedDirectory: URL
    package let source: StartupDirectorySource
    package let needsAccessRecovery: Bool
}

/// Resolves launch navigation independently from preference presentation. It is
/// the sole owner of fallback probing and saved-folder access-policy validation.
package final class StartupNavigationService {
    private let settings: SettingsPersisting
    private let accessPolicyOverride: SandboxFileAccessPolicy?
    private let grantService: FolderAccessGrantService
    private let home: () -> URL
    private let documents: () -> URL
    private let applicationSupport: () -> URL

    package init(
        settings: SettingsPersisting,
        accessPolicy: SandboxFileAccessPolicy? = nil,
        grantService: FolderAccessGrantService = .shared,
        homeDirectoryProvider: @escaping () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
        documentsDirectoryProvider: @escaping () -> URL = { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents") },
        applicationSupportDirectoryProvider: @escaping () -> URL = { SettingsRepository.defaultJSONURL.deletingLastPathComponent() }
    ) {
        self.settings = settings; accessPolicyOverride = accessPolicy; self.grantService = grantService
        home = homeDirectoryProvider; documents = documentsDirectoryProvider; applicationSupport = applicationSupportDirectoryProvider
    }

    package func resolution(for pane: PaneID) -> StartupDirectoryResolution {
        let s = settings.snapshot
        let selected = pane == .left ? s.startupLeftDirectory : s.startupRightDirectory
        let visited = pane == .left ? s.lastLeftDirectory : s.lastRightDirectory
        let fallback = defaultDirectory(for: pane)
        let path = selected ?? visited ?? fallback.path
        let source: StartupDirectorySource = selected != nil ? .userSelected : (visited != nil ? .lastVisited : .default)
        let requested = URL(fileURLWithPath: path, isDirectory: true)
        guard !policy.canAccess(requested) else { return .init(directory: requested, requestedDirectory: requested, source: source, needsAccessRecovery: false) }
        return .init(directory: policy.validatedDirectory(fallback), requestedDirectory: requested, source: source, needsAccessRecovery: source == .userSelected)
    }

    package func validatedSavedDirectory(path: String?, fallback: URL) -> URL {
        policy.validatedDirectory(path.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? fallback, fallback: fallback)
    }

    private var policy: SandboxFileAccessPolicy {
        if let accessPolicyOverride { return accessPolicyOverride }
        return SandboxFileAccessPolicy(isEnabled: settings.snapshot.experimentalSandboxEnabled ?? false, rootURL: ExperimentalFlags.appSandboxRoot, grantService: grantService)
    }

    private func defaultDirectory(for pane: PaneID) -> URL {
        if settings.snapshot.experimentalSandboxEnabled ?? false {
            let name = pane == .left ? "Left Pane" : "Right Pane"
            return policy.validatedDirectory(ExperimentalFlags.appSandboxRoot.appendingPathComponent(name, isDirectory: true))
        }
        let candidates = pane == .left ? [home(), documents()] : [home()]
        if let accessible = candidates.first(where: { policy.canAccess($0) }) { return accessible }
        let support = applicationSupport(); try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return policy.canAccess(support) ? support : policy.validatedDirectory(support)
    }
}
