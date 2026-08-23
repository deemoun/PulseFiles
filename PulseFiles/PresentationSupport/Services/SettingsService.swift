import AppKit
import PulseFilesModels
import PulseFilesServices
import PulseFilesUtilities

protocol SettingsPreferences: AnyObject {
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

protocol AppearanceSettingsProviding: AnyObject {
    var defaultSidebarVisible: Bool { get set }; var defaultSinglePaneMode: Bool { get set }
    var liquidGlassEnabled: Bool { get set }; var preferredSidebarWidth: Double { get set }
    var fileColorScheme: FileColorScheme { get set }; func resetFileColorScheme()
}
protocol GeneralSettingsProviding: AnyObject {
    var appLanguage: AppLanguage { get set }; var confirmCopyOperations: Bool { get set }
    var confirmMoveOperations: Bool { get set }; var confirmDeleteOperations: Bool { get set }
    var permanentlyDeleteInsteadOfTrash: Bool { get set }
}
protocol NavigationSettingsProviding: AnyObject {
    var lastLeftDirectory: URL { get }; var lastRightDirectory: URL { get }
    var startupLeftDirectory: URL? { get set }; var startupRightDirectory: URL? { get set }
    var scratchDirectory: URL? { get set }; var scratchFolderSelection: ScratchFolderSelection? { get set }
    var showHiddenFilesByDefault: Bool { get set }; var quickSearchMatchMode: QuickSearchMatchMode { get set }
    var quickSearchPresentation: QuickSearchPresentation { get set }
}
protocol ExperimentalSettingsProviding: AnyObject {
    var experimentalTerminalEnabled: Bool { get set }; var defaultTerminalVisible: Bool { get set }
    var experimentalSandboxEnabled: Bool { get set }
}

/// Presentation adapter for typed preferences. Persistence and launch navigation
/// are delegated to services that can be tested without loading AppKit.
final class SettingsService: SettingsPreferences, AppearanceSettingsProviding, GeneralSettingsProviding, NavigationSettingsProviding, ExperimentalSettingsProviding, TerminalSettingsProviding {
    static let appLanguageDefaultsKey = SettingsRepository.appLanguageDefaultsKey
    static var jsonSettingsURL: URL { SettingsRepository.defaultJSONURL }

    private let repository: SettingsPersisting
    private let startupNavigation: StartupNavigationService
    private let grantService: FolderAccessGrantService
    private let sessionState: WindowSessionState

    init(
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

    var lastLeftDirectory: URL { get { startupNavigation.validatedSavedDirectory(path: snapshot.lastLeftDirectory, fallback: startupDirectoryResolution(for: .left).directory) } set { change { $0.lastLeftDirectory = newValue.path } } }
    var lastRightDirectory: URL { get { startupNavigation.validatedSavedDirectory(path: snapshot.lastRightDirectory, fallback: startupDirectoryResolution(for: .right).directory) } set { change { $0.lastRightDirectory = newValue.path } } }
    var startupLeftDirectory: URL? { get { url(snapshot.startupLeftDirectory) } set { change { $0.startupLeftDirectory = newValue?.path } } }
    var startupRightDirectory: URL? { get { url(snapshot.startupRightDirectory) } set { change { $0.startupRightDirectory = newValue?.path } } }
    var launchLeftDirectory: URL { startupDirectoryResolution(for: .left).directory }
    var launchRightDirectory: URL { startupDirectoryResolution(for: .right).directory }
    func startupDirectoryResolution(for pane: PaneID) -> StartupDirectoryResolution { startupNavigation.resolution(for: pane) }

    var leftPaneTabRestoration: PaneRestorationState? { get { snapshot.leftPaneTabRestoration } set { change { $0.leftPaneTabRestoration = newValue } } }
    var rightPaneTabRestoration: PaneRestorationState? { get { snapshot.rightPaneTabRestoration } set { change { $0.rightPaneTabRestoration = newValue } } }
    func paneTabRestoration(for pane: PaneID) -> PaneRestorationState? { pane == .left ? leftPaneTabRestoration : rightPaneTabRestoration }
    func setPaneTabRestoration(_ value: PaneRestorationState?, for pane: PaneID) { if pane == .left { leftPaneTabRestoration = value } else { rightPaneTabRestoration = value } }

    var scratchDirectory: URL? { get { url(snapshot.scratchDirectory) } set { change { s in s.scratchDirectory = newValue?.path; if newValue == nil { s.scratchDirectoryIdentity = nil; s.scratchDirectoryResolvedPath = nil } } } }
    var scratchFolderSelection: ScratchFolderSelection? {
        get { guard let directory = scratchDirectory, let identity = snapshot.scratchDirectoryIdentity, let path = snapshot.scratchDirectoryResolvedPath else { return nil }; return .init(directory: directory, identity: identity, resolvedPath: path) }
        set { change { $0.scratchDirectoryIdentity = newValue?.identity; $0.scratchDirectoryResolvedPath = newValue?.resolvedPath } }
    }

    var defaultSidebarVisible: Bool { get { snapshot.defaultSidebarVisible ?? true } set { change { $0.defaultSidebarVisible = newValue } } }
    var appLanguage: AppLanguage { get { AppLanguage(rawValue: snapshot.appLanguage ?? "") ?? .english } set { change { $0.appLanguage = newValue.rawValue } } }
    var liquidGlassEnabled: Bool { get { snapshot.liquidGlassEnabled ?? false } set { change { $0.liquidGlassEnabled = newValue } } }
    var experimentalTerminalEnabled: Bool { get { snapshot.experimentalTerminalEnabled ?? false } set { change { $0.experimentalTerminalEnabled = newValue; if !newValue { $0.defaultTerminalVisible = false } } } }
    var hasAcknowledgedTerminalWarning: Bool { get { snapshot.hasAcknowledgedTerminalWarning ?? false } set { change { $0.hasAcknowledgedTerminalWarning = newValue } } }
    var defaultTerminalVisible: Bool { get { experimentalTerminalEnabled && (snapshot.defaultTerminalVisible ?? false) } set { change { $0.defaultTerminalVisible = self.experimentalTerminalEnabled && newValue } } }
    var defaultSinglePaneMode: Bool { get { snapshot.defaultSinglePaneMode ?? false } set { change { $0.defaultSinglePaneMode = newValue } } }
    var showHiddenFilesByDefault: Bool { get { snapshot.showHiddenFilesByDefault ?? false } set { change { $0.showHiddenFilesByDefault = newValue } } }
    var defaultPanePresentationMode: PanePresentationMode { get { snapshot.defaultPanePresentationMode ?? .list } set { change { $0.defaultPanePresentationMode = newValue } } }
    var leftPanePresentationMode: PanePresentationMode { get { snapshot.leftPanePresentationMode ?? defaultPanePresentationMode } set { change { $0.leftPanePresentationMode = newValue } } }
    var rightPanePresentationMode: PanePresentationMode { get { snapshot.rightPanePresentationMode ?? defaultPanePresentationMode } set { change { $0.rightPanePresentationMode = newValue } } }
    func presentationMode(for pane: PaneID) -> PanePresentationMode { pane == .left ? leftPanePresentationMode : rightPanePresentationMode }
    func setPresentationMode(_ value: PanePresentationMode, for pane: PaneID) { if pane == .left { leftPanePresentationMode = value } else { rightPanePresentationMode = value } }
    var quickSearchMatchMode: QuickSearchMatchMode { get { snapshot.quickSearchMatchMode ?? .contains } set { change { $0.quickSearchMatchMode = newValue } } }
    var quickSearchPresentation: QuickSearchPresentation { get { snapshot.quickSearchPresentation ?? .filterMatches } set { change { $0.quickSearchPresentation = newValue } } }
    var confirmCopyOperations: Bool { get { snapshot.confirmCopyOperations ?? true } set { change { $0.confirmCopyOperations = newValue } } }
    var confirmMoveOperations: Bool { get { snapshot.confirmMoveOperations ?? true } set { change { $0.confirmMoveOperations = newValue } } }
    var confirmDeleteOperations: Bool { get { snapshot.confirmDeleteOperations ?? true } set { change { $0.confirmDeleteOperations = newValue } } }
    var permanentlyDeleteInsteadOfTrash: Bool { get { snapshot.permanentlyDeleteInsteadOfTrash ?? false } set { change { $0.permanentlyDeleteInsteadOfTrash = newValue } } }
    var experimentalSandboxEnabled: Bool {
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

    var fileColorScheme: FileColorScheme {
        get { guard let values = snapshot.fileColorScheme else { return .default }; return FileColorScheme(colors: values.reduce(into: [:]) { result, entry in if let category = FileVisualCategory(rawValue: entry.key) { result[category] = StoredColorAppKitAdapter.color(from: entry.value) } }) }
        set { change { $0.fileColorScheme = newValue.colors.reduce(into: [:]) { $0[$1.key.rawValue] = StoredColorAppKitAdapter.rgba(from: $1.value) } } }
    }
    func resetFileColorScheme() { change { $0.fileColorScheme = nil } }
    var folderAccessGrants: [FolderAccessGrant] { get { grantService.grants } set { grantService.grants = newValue; _ = try? repository.writeSettingsJSON() } }
    var defaultSortDescriptor: FileSortDescriptor { get { snapshot.defaultSortDescriptor ?? FileSortDescriptor() } set { change { $0.defaultSortDescriptor = newValue } } }
    func sortDescriptor(for pane: PaneID) -> FileSortDescriptor { pane == .left ? (snapshot.leftPaneSortDescriptor ?? defaultSortDescriptor) : (snapshot.rightPaneSortDescriptor ?? defaultSortDescriptor) }
    func setSortDescriptor(_ value: FileSortDescriptor, for pane: PaneID) { change { if pane == .left { $0.leftPaneSortDescriptor = value } else { $0.rightPaneSortDescriptor = value } } }
    var preferredSidebarWidth: Double { get { snapshot.preferredSidebarWidth ?? 260 } set { change { $0.preferredSidebarWidth = min(max(newValue, 220), 340) } } }
    var isSidebarVisible: Bool { get { defaultSidebarVisible } set { defaultSidebarVisible = newValue } }
    var sidebarWidth: Double { get { preferredSidebarWidth } set { preferredSidebarWidth = newValue } }
    var isTerminalVisible: Bool { get { experimentalTerminalEnabled && (sessionState.runtimeTerminalVisible ?? defaultTerminalVisible) } set { sessionState.runtimeTerminalVisible = experimentalTerminalEnabled && newValue } }
    func importJSONIfChanged() { repository.importJSONIfChanged() }
    @discardableResult func writeSettingsJSON() throws -> URL { try repository.writeSettingsJSON() }
}
