import AppKit
import PulseFilesModels
import PulseFilesServices
import PulseFilesUtilities

package protocol SettingsPreferences: AnyObject {
    var appLanguage: AppLanguage { get set }
    var defaultSidebarVisible: Bool { get set }
    var liquidGlassEnabled: Bool { get set }
    var experimentalTerminalEnabled: Bool { get set }
    var hasAcknowledgedTerminalWarning: Bool { get set }
    var defaultTerminalVisible: Bool { get set }
    var defaultSinglePaneMode: Bool { get set }
    var showHiddenFilesByDefault: Bool { get set }
    var quickSearchMatchMode: QuickSearchMatchMode { get set }
    var quickSearchPresentation: QuickSearchPresentation { get set }
    var confirmCopyOperations: Bool { get set }
    var confirmMoveOperations: Bool { get set }
    var confirmDeleteOperations: Bool { get set }
    var permanentlyDeleteInsteadOfTrash: Bool { get set }
    var preferredSidebarWidth: Double { get set }
}

package protocol AppearanceSettingsProviding: AnyObject {
    var defaultSidebarVisible: Bool { get set }; var defaultSinglePaneMode: Bool { get set }
    var liquidGlassEnabled: Bool { get set }; var preferredSidebarWidth: Double { get set }
    var fileColorScheme: FileColorScheme { get set }; func resetFileColorScheme()
}
package protocol GeneralSettingsProviding: AnyObject {
    var appLanguage: AppLanguage { get set }; var confirmCopyOperations: Bool { get set }
    var confirmMoveOperations: Bool { get set }; var confirmDeleteOperations: Bool { get set }
    var permanentlyDeleteInsteadOfTrash: Bool { get set }
}
package protocol NavigationSettingsProviding: AnyObject {
    var lastLeftDirectory: URL { get }; var lastRightDirectory: URL { get }
    var startupLeftDirectory: URL? { get set }; var startupRightDirectory: URL? { get set }
    var scratchDirectory: URL? { get set }; var scratchFolderSelection: ScratchFolderSelection? { get set }
    var showHiddenFilesByDefault: Bool { get set }; var quickSearchMatchMode: QuickSearchMatchMode { get set }
    var quickSearchPresentation: QuickSearchPresentation { get set }
}
package protocol ExperimentalSettingsProviding: AnyObject {
    var experimentalTerminalEnabled: Bool { get set }; var defaultTerminalVisible: Bool { get set }
    var experimentalSandboxEnabled: Bool { get set }
}

/// Presentation adapter for typed preferences. Persistence and launch navigation
/// are delegated to services that can be tested without loading AppKit.
package final class SettingsService: SettingsPreferences, AppearanceSettingsProviding, GeneralSettingsProviding, NavigationSettingsProviding, ExperimentalSettingsProviding, TerminalSettingsProviding {
    package static let appLanguageDefaultsKey = SettingsRepository.appLanguageDefaultsKey
    package static var jsonSettingsURL: URL { SettingsRepository.defaultJSONURL }

    private let repository: SettingsPersisting
    private let startupNavigation: StartupNavigationService
    private let grantService: FolderAccessGrantService
    private let sessionState: WindowSessionState

    package init(
        defaults: UserDefaults = .standard,
        accessPolicy: SandboxFileAccessPolicy? = nil,
        folderAccessBookmarkResolver: FolderAccessBookmarkResolving = SystemFolderAccessBookmarkResolver(),
        jsonSettingsURLProvider: (() -> URL)? = nil,
        homeDirectoryProvider: @escaping () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
        documentsDirectoryProvider: @escaping () -> URL = { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true) },
        applicationSupportDirectoryProvider: @escaping () -> URL = { SettingsRepository.defaultJSONURL.deletingLastPathComponent() },
        sessionState: WindowSessionState = WindowSessionState()
    ) {
        let repository = SettingsRepository(defaults: defaults, jsonURLProvider: jsonSettingsURLProvider)
        let grants = FolderAccessGrantService(defaults: defaults, resolver: folderAccessBookmarkResolver)
        self.repository = repository
        grantService = grants
        self.sessionState = sessionState
        startupNavigation = StartupNavigationService(settings: repository, accessPolicy: accessPolicy, grantService: grants, homeDirectoryProvider: homeDirectoryProvider, documentsDirectoryProvider: documentsDirectoryProvider, applicationSupportDirectoryProvider: applicationSupportDirectoryProvider)
    }

    private var snapshot: SettingsSnapshot { repository.snapshot }
    private func change(_ mutation: @escaping (inout SettingsSnapshot) -> Void) { repository.update(mutation) }
    private func url(_ path: String?) -> URL? { path.map { URL(fileURLWithPath: $0, isDirectory: true) } }

    package var lastLeftDirectory: URL { get { startupNavigation.validatedSavedDirectory(path: snapshot.lastLeftDirectory, fallback: startupDirectoryResolution(for: .left).directory) } set { change { $0.lastLeftDirectory = newValue.path } } }
    package var lastRightDirectory: URL { get { startupNavigation.validatedSavedDirectory(path: snapshot.lastRightDirectory, fallback: startupDirectoryResolution(for: .right).directory) } set { change { $0.lastRightDirectory = newValue.path } } }
    package var startupLeftDirectory: URL? { get { url(snapshot.startupLeftDirectory) } set { change { $0.startupLeftDirectory = newValue?.path } } }
    package var startupRightDirectory: URL? { get { url(snapshot.startupRightDirectory) } set { change { $0.startupRightDirectory = newValue?.path } } }
    package var launchLeftDirectory: URL { startupDirectoryResolution(for: .left).directory }
    package var launchRightDirectory: URL { startupDirectoryResolution(for: .right).directory }
    package func startupDirectoryResolution(for pane: PaneID) -> StartupDirectoryResolution { startupNavigation.resolution(for: pane) }

    package var leftPaneTabRestoration: PaneRestorationState? { get { snapshot.leftPaneTabRestoration } set { change { $0.leftPaneTabRestoration = newValue } } }
    package var rightPaneTabRestoration: PaneRestorationState? { get { snapshot.rightPaneTabRestoration } set { change { $0.rightPaneTabRestoration = newValue } } }
    package func paneTabRestoration(for pane: PaneID) -> PaneRestorationState? { pane == .left ? leftPaneTabRestoration : rightPaneTabRestoration }
    package func setPaneTabRestoration(_ value: PaneRestorationState?, for pane: PaneID) { if pane == .left { leftPaneTabRestoration = value } else { rightPaneTabRestoration = value } }

    package var scratchDirectory: URL? { get { url(snapshot.scratchDirectory) } set { change { s in s.scratchDirectory = newValue?.path; if newValue == nil { s.scratchDirectoryIdentity = nil; s.scratchDirectoryResolvedPath = nil } } } }
    package var scratchFolderSelection: ScratchFolderSelection? {
        get { guard let directory = scratchDirectory, let identity = snapshot.scratchDirectoryIdentity, let path = snapshot.scratchDirectoryResolvedPath else { return nil }; return .init(directory: directory, identity: identity, resolvedPath: path) }
        set { change { $0.scratchDirectoryIdentity = newValue?.identity; $0.scratchDirectoryResolvedPath = newValue?.resolvedPath } }
    }

    package var defaultSidebarVisible: Bool { get { snapshot.defaultSidebarVisible ?? true } set { change { $0.defaultSidebarVisible = newValue } } }
    package var appLanguage: AppLanguage { get { AppLanguage(rawValue: snapshot.appLanguage ?? "") ?? .english } set { change { $0.appLanguage = newValue.rawValue } } }
    package var liquidGlassEnabled: Bool { get { snapshot.liquidGlassEnabled ?? false } set { change { $0.liquidGlassEnabled = newValue } } }
    package var experimentalTerminalEnabled: Bool { get { snapshot.experimentalTerminalEnabled ?? false } set { change { $0.experimentalTerminalEnabled = newValue; if !newValue { $0.defaultTerminalVisible = false } } } }
    package var hasAcknowledgedTerminalWarning: Bool { get { snapshot.hasAcknowledgedTerminalWarning ?? false } set { change { $0.hasAcknowledgedTerminalWarning = newValue } } }
    package var defaultTerminalVisible: Bool { get { experimentalTerminalEnabled && (snapshot.defaultTerminalVisible ?? false) } set { change { $0.defaultTerminalVisible = self.experimentalTerminalEnabled && newValue } } }
    package var defaultSinglePaneMode: Bool { get { snapshot.defaultSinglePaneMode ?? false } set { change { $0.defaultSinglePaneMode = newValue } } }
    package var showHiddenFilesByDefault: Bool { get { snapshot.showHiddenFilesByDefault ?? false } set { change { $0.showHiddenFilesByDefault = newValue } } }
    package var defaultPanePresentationMode: PanePresentationMode { get { snapshot.defaultPanePresentationMode ?? .list } set { change { $0.defaultPanePresentationMode = newValue } } }
    package var leftPanePresentationMode: PanePresentationMode { get { snapshot.leftPanePresentationMode ?? defaultPanePresentationMode } set { change { $0.leftPanePresentationMode = newValue } } }
    package var rightPanePresentationMode: PanePresentationMode { get { snapshot.rightPanePresentationMode ?? defaultPanePresentationMode } set { change { $0.rightPanePresentationMode = newValue } } }
    package func presentationMode(for pane: PaneID) -> PanePresentationMode { pane == .left ? leftPanePresentationMode : rightPanePresentationMode }
    package func setPresentationMode(_ value: PanePresentationMode, for pane: PaneID) { if pane == .left { leftPanePresentationMode = value } else { rightPanePresentationMode = value } }
    package var quickSearchMatchMode: QuickSearchMatchMode { get { snapshot.quickSearchMatchMode ?? .contains } set { change { $0.quickSearchMatchMode = newValue } } }
    package var quickSearchPresentation: QuickSearchPresentation { get { snapshot.quickSearchPresentation ?? .filterMatches } set { change { $0.quickSearchPresentation = newValue } } }
    package var confirmCopyOperations: Bool { get { snapshot.confirmCopyOperations ?? true } set { change { $0.confirmCopyOperations = newValue } } }
    package var confirmMoveOperations: Bool { get { snapshot.confirmMoveOperations ?? true } set { change { $0.confirmMoveOperations = newValue } } }
    package var confirmDeleteOperations: Bool { get { snapshot.confirmDeleteOperations ?? true } set { change { $0.confirmDeleteOperations = newValue } } }
    package var permanentlyDeleteInsteadOfTrash: Bool { get { snapshot.permanentlyDeleteInsteadOfTrash ?? false } set { change { $0.permanentlyDeleteInsteadOfTrash = newValue } } }
    package var experimentalSandboxEnabled: Bool {
        get {
#if DEBUG
            snapshot.experimentalSandboxEnabled ?? false
#else
            false
#endif
        }
        set {
#if DEBUG
            change { $0.experimentalSandboxEnabled = newValue }
#else
            change { $0.experimentalSandboxEnabled = nil }
#endif
        }
    }

    package var fileColorScheme: FileColorScheme {
        get { guard let values = snapshot.fileColorScheme else { return .default }; return FileColorScheme(colors: values.reduce(into: [:]) { result, entry in if let category = FileVisualCategory(rawValue: entry.key) { result[category] = StoredColorAppKitAdapter.color(from: entry.value) } }) }
        set { change { $0.fileColorScheme = newValue.colors.reduce(into: [:]) { $0[$1.key.rawValue] = StoredColorAppKitAdapter.rgba(from: $1.value) } } }
    }
    package func resetFileColorScheme() { change { $0.fileColorScheme = nil } }
    package var folderAccessGrants: [FolderAccessGrant] { get { grantService.grants } set { grantService.grants = newValue; _ = try? repository.writeSettingsJSON() } }
    package var defaultSortDescriptor: FileSortDescriptor { get { snapshot.defaultSortDescriptor ?? FileSortDescriptor() } set { change { $0.defaultSortDescriptor = newValue } } }
    package func sortDescriptor(for pane: PaneID) -> FileSortDescriptor { pane == .left ? (snapshot.leftPaneSortDescriptor ?? defaultSortDescriptor) : (snapshot.rightPaneSortDescriptor ?? defaultSortDescriptor) }
    package func setSortDescriptor(_ value: FileSortDescriptor, for pane: PaneID) { change { if pane == .left { $0.leftPaneSortDescriptor = value } else { $0.rightPaneSortDescriptor = value } } }
    package var preferredSidebarWidth: Double { get { snapshot.preferredSidebarWidth ?? 260 } set { change { $0.preferredSidebarWidth = min(max(newValue, 220), 340) } } }
    package var isSidebarVisible: Bool { get { defaultSidebarVisible } set { defaultSidebarVisible = newValue } }
    package var sidebarWidth: Double { get { preferredSidebarWidth } set { preferredSidebarWidth = newValue } }
    package var isTerminalVisible: Bool { get { experimentalTerminalEnabled && (sessionState.runtimeTerminalVisible ?? defaultTerminalVisible) } set { sessionState.runtimeTerminalVisible = experimentalTerminalEnabled && newValue } }
    package func importJSONIfChanged() { repository.importJSONIfChanged() }
    @discardableResult func writeSettingsJSON() throws -> URL { try repository.writeSettingsJSON() }
}
