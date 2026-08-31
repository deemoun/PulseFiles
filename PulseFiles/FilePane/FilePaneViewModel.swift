// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@MainActor
package final class FilePaneViewModel {
    private typealias PendingHistoryTransition = PaneNavigationStateMachine.HistoryTransition
    private let fileSystem: FileSystemServicing
    private let accessPolicy: any BrowseAccessPolicy
    package var fileSystemForCompositionTesting: any FileSystemServicing { fileSystem }
    package var accessPolicyIdentityForCompositionTesting: ObjectIdentifier { ObjectIdentifier(accessPolicy) }
    private let loadCoordinator: DirectoryLoadCoordinator
    private let memoryPressureSource: DispatchSourceMemoryPressure
    private var partialRefreshRetryCount = 0
    private let maximumPartialRefreshRetries = 2
    private var activeLoadID = 0
    /// Monotonically increases for each filesystem notification received for the
    /// displayed directory. A load records the value it started with so an event
    /// that arrives while it is running cannot be lost.
    private var directoryChangeGeneration = 0
    private var pendingRefreshGeneration: Int?

    private var navigation: PaneNavigationStateMachine
    private(set) var state: PaneState {
        get { navigation.state }
        set { navigation.state = newValue }
    }
    private(set) var items: [FileItem] = []
    private(set) var isLoading: Bool { loadCoordinator.isLoading }
    private(set) var errorMessage: String?
    private(set) var loadFailure: DirectoryLoadFailure?
    /// Non-nil when a directory enumeration omitted children because their metadata
    /// could not be read. The visible items are not a confirmed-current snapshot.
    private(set) var partialRefreshFailure: DirectoryContentsReadError?
    private(set) var isPartialRefreshRetryScheduled: Bool { loadCoordinator.isRetryScheduled }
    package private(set) var searchQuery = ""
    private(set) var quickSearchMatchMode: QuickSearchMatchMode
    private(set) var quickSearchPresentation: QuickSearchPresentation

    package var onChange: (() -> Void)?
    package var onDirectoryChanged: ((URL) -> Void)?
    package var onDisplayPreferencesChanged: ((Bool, FileSortDescriptor) -> Void)?
    package var onTabsChanged: (() -> Void)?

    struct DirectoryLoadFailure {
        let directory: URL
        let error: Error

        var message: String { error.localizedDescription }
        var isOutsideSandbox: Bool {
            if case SandboxAccessError.outsideExperimentalSandbox = error { return true }
            return false
        }

        var isMissingDirectory: Bool {
            let nsError = error as NSError
            return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
                || nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
        }

        var isTimedOut: Bool {
            error is DirectoryLoadTimeoutError
        }

        var isRetryable: Bool {
            isTimedOut
        }
    }

    package init(
        initialDirectory: URL,
        showsHiddenFiles: Bool = false,
        sort: FileSortDescriptor = FileSortDescriptor(),
        restoration: PaneRestorationState? = nil,
        fileSystem: FileSystemServicing,
        accessPolicy: any BrowseAccessPolicy,
        directoryLoadTimeout: TimeInterval = 15,
        directoryMonitor: DirectoryMonitor = DirectoryMonitor(),
        snapshotCache: DirectorySnapshotCache = DirectorySnapshotCache(),
        quickSearchMatchMode: QuickSearchMatchMode = .contains,
        quickSearchPresentation: QuickSearchPresentation = .filterMatches
    ) {
        precondition(directoryLoadTimeout > 0 && directoryLoadTimeout.isFinite)
        self.fileSystem = fileSystem
        self.accessPolicy = accessPolicy
        self.loadCoordinator = DirectoryLoadCoordinator(
            fileSystem: fileSystem, accessPolicy: accessPolicy, snapshotCache: snapshotCache,
            monitor: directoryMonitor, timeout: directoryLoadTimeout
        )
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        self.quickSearchMatchMode = quickSearchMatchMode
        self.quickSearchPresentation = quickSearchPresentation
        let validatedDirectory = accessPolicy.validatedDirectory(initialDirectory)
        let restoredTabs = restoration?.tabs.compactMap { saved -> PaneTabState? in
            guard accessPolicy.canAccess(saved.directory),
                  (try? saved.directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let directory = saved.directory.standardizedFileURL
            return PaneTabState(id: saved.id, currentDirectory: directory, history: NavigationHistory(initialURL: directory), sort: saved.sort, showsHiddenFiles: saved.showsHiddenFiles)
        } ?? []
        if restoredTabs.isEmpty {
            navigation = PaneNavigationStateMachine(state: PaneState(currentDirectory: validatedDirectory, history: NavigationHistory(initialURL: validatedDirectory), sort: sort, showsHiddenFiles: showsHiddenFiles))
        } else {
            navigation = PaneNavigationStateMachine(state: PaneState(tabs: restoredTabs, activeTabID: restoration?.activeTabID))
        }
        loadCoordinator.onMonitorChange = { [weak self] in
            self?.reloadAfterExternalDirectoryChange()
        }
        memoryPressureSource.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.loadCoordinator.clearCache()
            }
        }
        memoryPressureSource.resume()
    }

    deinit {
        memoryPressureSource.cancel()
        onChange = nil
        onDirectoryChanged = nil
        onDisplayPreferencesChanged = nil
    }


    package var currentDirectory: URL { state.currentDirectory }
    /// Identifies the directory load currently represented by the pane state.
    package var loadGeneration: Int { activeLoadID }
    package var isAccessRestrictedToExperimentalSandbox: Bool { accessPolicy.isEnabled }
    package var sortDescriptor: FileSortDescriptor { state.sort }
    package var showsHiddenFiles: Bool { state.showsHiddenFiles }
    package var focusedURL: URL? { state.focusedURL }
    package var backDestination: URL? { state.history.backStack.last }
    package var navigationHistory: NavigationHistory { state.history }
    package var tabs: [PaneTabState] { state.tabs }
    package var activeTabID: UUID { state.activeTabID }
    package var visibleItems: [FileItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        guard quickSearchPresentation == .filterMatches else { return items }
        return items.filter { match(for: $0) != nil }
    }

    package func match(for item: FileItem) -> QuickSearchMatch? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        return QuickSearchMatcher.match(query, in: item.filename, mode: quickSearchMatchMode)
    }

    package func setQuickSearchOptions(matchMode: QuickSearchMatchMode, presentation: QuickSearchPresentation) {
        guard quickSearchMatchMode != matchMode || quickSearchPresentation != presentation else { return }
        quickSearchMatchMode = matchMode
        quickSearchPresentation = presentation
        onChange?()
    }

    package func validateAccess(to url: URL) throws {
        try accessPolicy.validateAccess(to: url)
    }

    /// Captures only logical browser state, allowing panes to exchange state
    /// without exchanging their controller/view instances.
    package func logicalStateSnapshot() -> PaneState {
        var snapshot = state
        snapshot.searchQuery = searchQuery
        return snapshot
    }

    package func setFocusedURL(_ url: URL?) {
        state.setFocus(url)
    }

    package func setMarkedURLs(_ urls: Set<URL>) {
        state.markedURLs = urls
    }

    /// Restores a snapshot atomically after its destination passes the same
    /// sandbox policy used by ordinary navigation.
    package func restoreLogicalState(_ snapshot: PaneState, onLoaded: (() -> Void)? = nil) throws {
        try snapshot.tabs.forEach { try accessPolicy.validateAccess(to: $0.currentDirectory) }
        var restored = snapshot
        restored.currentDirectory = snapshot.currentDirectory.standardizedFileURL
        navigation.restore(restored)
        searchQuery = restored.searchQuery
        load(directory: restored.currentDirectory, addToHistory: false, forceRefresh: false, onLoaded: onLoaded)
        onTabsChanged?()
    }

    @discardableResult
    package func newTab(directory: URL? = nil) -> UUID {
        let requested = directory ?? state.currentDirectory
        let validated = accessPolicy.validatedDirectory(requested, fallback: state.currentDirectory)
        let tab = PaneTabState(
            currentDirectory: validated,
            history: NavigationHistory(initialURL: validated),
            sort: state.sort,
            showsHiddenFiles: state.showsHiddenFiles
        )
        state.tabs.append(tab)
        selectTab(id: tab.id)
        return tab.id
    }

    @discardableResult
    package func closeTab(id: UUID? = nil) -> Bool {
        let previousCount = state.tabs.count
        let wasActive = navigation.closeTab(id: id)
        guard state.tabs.count < previousCount else { return false }
        if wasActive { activateCurrentTab() }
        onTabsChanged?()
        return true
    }

    package func selectTab(id: UUID) {
        guard navigation.activateTab(id: id, savingSearchQuery: searchQuery) else { return }
        activateCurrentTab()
        onTabsChanged?()
    }

    package func selectNextTab() { selectRelativeTab(offset: 1) }
    package func selectPreviousTab() { selectRelativeTab(offset: -1) }

    @discardableResult
    package func reorderTab(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        guard state.tabs.indices.contains(sourceIndex), destinationIndex >= 0, destinationIndex < state.tabs.count,
              sourceIndex != destinationIndex else { return false }
        let tab = state.tabs.remove(at: sourceIndex)
        state.tabs.insert(tab, at: destinationIndex)
        onTabsChanged?()
        return true
    }

    private func selectRelativeTab(offset: Int) {
        guard state.tabs.count > 1 else { return }
        let index = (state.activeTabIndex + offset + state.tabs.count) % state.tabs.count
        selectTab(id: state.tabs[index].id)
    }

    private func activateCurrentTab() {
        searchQuery = state.searchQuery
        load(directory: state.currentDirectory, addToHistory: false, forceRefresh: false)
    }

    /// Keeps parent-row presentation and keyboard navigation subject to the
    /// same access policy as every other directory navigation.
    package func canNavigate(to directory: URL) -> Bool {
        accessPolicy.canAccess(directory)
    }

    package func loadCurrentDirectory(forceRefresh: Bool = false, onLoaded: (() -> Void)? = nil) {
        load(directory: state.currentDirectory, addToHistory: false, forceRefresh: forceRefresh, onLoaded: onLoaded)
    }

    package func retryFailedDirectoryLoad() {
        guard loadFailure?.isRetryable == true else { return }
        load(directory: state.currentDirectory, addToHistory: false, forceRefresh: true)
    }

    package func reloadAfterExternalDirectoryChange() {
        loadCoordinator.invalidate(state.currentDirectory)
        directoryChangeGeneration += 1
        pendingRefreshGeneration = directoryChangeGeneration
        startPendingExternalRefreshIfNeeded()
    }

    package func invalidateCurrentDirectorySnapshot() {
        loadCoordinator.invalidate(state.currentDirectory)
    }

    package func navigate(to url: URL) {
        let validatedURL = accessPolicy.validatedDirectory(url, fallback: state.currentDirectory)
        if validatedURL != url {
            DiagnosticLogger.log(.warning, category: "FilePane", "Rejected navigation outside sandbox: requested=\(DiagnosticLogger.sanitizedPath(url)); redirected=\(DiagnosticLogger.sanitizedPath(validatedURL))")
        }
        load(directory: validatedURL, addToHistory: true)
    }

    /// Leaves a directory whose volume was removed before a stale file descriptor can
    /// generate further directory events. The fallback is always policy-validated.
    @discardableResult
    package func fallBackIfCurrentDirectoryIsUnavailable(
        directoryExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        preferredFallback: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        guard !directoryExists(state.currentDirectory) else { return false }
        loadCoordinator.stopMonitoring()
        loadCoordinator.cancel()
        let fallback = accessPolicy.validatedDirectory(preferredFallback, fallback: accessPolicy.rootURL)
        items = []
        searchQuery = ""
        state.currentDirectory = fallback
        state.history.visit(fallback)
        load(directory: fallback, addToHistory: false)
        return true
    }

    package func goParent() {
        let parent = state.currentDirectory.deletingLastPathComponent()
        guard parent != state.currentDirectory else {
            DiagnosticLogger.log(.debug, category: "FilePane", "Rejected parent navigation at filesystem root")
            return
        }
        guard accessPolicy.canAccess(parent) else {
            DiagnosticLogger.log(.warning, category: "FilePane", "Rejected parent navigation outside sandbox: current=\(DiagnosticLogger.sanitizedPath(state.currentDirectory)); parent=\(DiagnosticLogger.sanitizedPath(parent))")
            return
        }
        navigate(to: parent)
    }

    package func navigateToSandboxRoot() {
        navigate(to: accessPolicy.validatedDirectory(ExperimentalFlags.appSandboxRoot))
    }

    package func navigateToParentOfFailedDirectory() {
        guard let failedDirectory = loadFailure?.directory else { return }
        let parent = failedDirectory.deletingLastPathComponent()
        guard parent != failedDirectory else { return }
        navigate(to: accessPolicy.validatedDirectory(parent, fallback: state.currentDirectory))
    }

    package func goBack() {
        guard let transition = navigation.backTransition() else { return }
        loadHistoryDestination(transition.directory, transition: transition)
    }

    package func goForward() {
        guard let transition = navigation.forwardTransition() else { return }
        loadHistoryDestination(transition.directory, transition: transition)
    }

    private func loadHistoryDestination(_ directory: URL, transition: PendingHistoryTransition) {
        do {
            // History may outlive a removable volume or security-scoped grant, so
            // revalidate it before starting (and again inside the scoped read).
            try accessPolicy.validateAccess(to: directory)
        } catch {
            navigation.rollBack(transition)
            loadFailure = DirectoryLoadFailure(directory: directory, error: error)
            errorMessage = error.localizedDescription
            onChange?()
            return
        }
        load(directory: directory, addToHistory: false, historyTransition: transition)
    }

    package func toggleHiddenFiles() {
        setShowsHiddenFiles(!state.showsHiddenFiles)
    }

    package func setShowsHiddenFiles(_ showsHiddenFiles: Bool) {
        guard state.showsHiddenFiles != showsHiddenFiles else { return }
        state.showsHiddenFiles = showsHiddenFiles
        persistDisplayPreferences()
        loadCurrentDirectory()
    }

    package func setSort(_ key: FileSortKey) {
        if state.sort.key == key {
            state.sort.ascending.toggle()
        } else {
            state.sort.key = key
            state.sort.ascending = true
        }
        persistDisplayPreferences()
        applyCurrentSort()
    }

    package func setSort(_ key: FileSortKey, ascending: Bool) {
        var descriptor = state.sort
        descriptor.key = key
        descriptor.ascending = ascending
        guard state.sort != descriptor else { return }
        state.sort = descriptor
        persistDisplayPreferences()
        applyCurrentSort()
    }

    package func setSortDescriptor(_ descriptor: FileSortDescriptor) {
        guard state.sort != descriptor else { return }
        state.sort = descriptor
        persistDisplayPreferences()
        applyCurrentSort()
    }

    package func setSearchQuery(_ query: String) {
        guard searchQuery != query else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = query
        state.searchQuery = query
        DiagnosticLogger.log(.debug, category: "FilePane", "Search filter changed: active=\(!trimmedQuery.isEmpty); queryLength=\(trimmedQuery.count); totalItems=\(items.count); visibleItems=\(visibleItems.count)")
        onChange?()
    }

    private func applyCurrentSort() {
        items = FileSystemService.sorted(items, descriptor: state.sort)
        onChange?()
    }

    private func persistDisplayPreferences() {
        onDisplayPreferencesChanged?(state.showsHiddenFiles, state.sort)
    }

    private func startPendingExternalRefreshIfNeeded() {
        guard !isLoading, let generation = pendingRefreshGeneration else { return }

        // Clearing happens only as the refresh is actually started. Events that
        // arrive after this point receive a newer generation and remain pending.
        pendingRefreshGeneration = nil
        load(
            directory: state.currentDirectory,
            addToHistory: false,
            forceRefresh: true,
            changeGeneration: generation
        )
    }

    private func load(
        directory: URL,
        addToHistory: Bool,
        historyTransition: PendingHistoryTransition? = nil,
        forceRefresh: Bool = false,
        changeGeneration: Int? = nil,
        onLoaded: (() -> Void)? = nil
    ) {
        loadCoordinator.cancel()
        activeLoadID = loadID
        let loadChangeGeneration = changeGeneration ?? directoryChangeGeneration
        DiagnosticLogger.log(.info, category: "FilePane", "Directory load started: path=\(DiagnosticLogger.sanitizedPath(directory)); includeHidden=\(state.showsHiddenFiles); sort=\(state.sort.key.rawValue); ascending=\(state.sort.ascending)")
        errorMessage = nil
        loadFailure = nil
        onChange?()

        let previousDirectory = state.currentDirectory
        let previousItems = items
        let previousListingWasComplete = partialRefreshFailure == nil
        if directory != previousDirectory {
            partialRefreshFailure = nil
            partialRefreshRetryCount = 0
        }

        let includeHidden = state.showsHiddenFiles
        let sort = state.sort

        loadCoordinator.load(.init(
            directory: directory,
            includeHidden: includeHidden,
            sort: sort,
            forceRefresh: forceRefresh
        )) { [weak self] generation, result in
            guard let self else { return }
            switch result {
            case .success(let directoryContents):
                self.finishSuccessfulLoad(
                    loadID: generation,
                    directory: directory,
                    directoryContents: directoryContents,
                    previousDirectory: previousDirectory,
                    previousItems: previousItems,
                    previousListingWasComplete: previousListingWasComplete,
                    addToHistory: addToHistory,
                    historyTransition: historyTransition,
                    changeGeneration: loadChangeGeneration,
                    onLoaded: onLoaded
                )
            case .failure(let error):
                self.finishFailedLoad(
                    loadID: generation,
                    directory: directory,
                    error: error,
                    previousDirectory: previousDirectory,
                    previousItems: previousItems,
                    historyTransition: historyTransition,
                    changeGeneration: loadChangeGeneration
                )
            }
        }
        activeLoadID = loadCoordinator.generation
    }

    private func finishSuccessfulLoad(
        loadID: Int,
        directory: URL,
        directoryContents: DirectoryContentsResult,
        previousDirectory: URL,
        previousItems: [FileItem],
        previousListingWasComplete: Bool,
        addToHistory: Bool,
        historyTransition: PendingHistoryTransition?,
        changeGeneration: Int,
        onLoaded: (() -> Void)?
    ) {
        guard isCurrentLoad(loadID) else { return }
        DiagnosticLogger.log(.info, category: "FilePane", "Directory load completed: path=\(DiagnosticLogger.sanitizedPath(directory)); itemCount=\(directoryContents.items.count); metadataFailures=\(directoryContents.itemReadFailures.count)")
        let partialFailure = directoryContents.isComplete ? nil : DirectoryContentsReadError(failures: directoryContents.itemReadFailures)
        if partialFailure == nil {
            items = directoryContents.items
            partialRefreshFailure = nil
            partialRefreshRetryCount = 0
        } else if directory == previousDirectory, previousListingWasComplete {
            items = previousItems
            partialRefreshFailure = partialFailure
        } else {
            items = directoryContents.items
            partialRefreshFailure = partialFailure
        }
        navigation.commitDirectory(directory, addToHistory: addToHistory, transition: historyTransition)
        onDirectoryChanged?(directory)
        onTabsChanged?()
        loadCoordinator.monitor(directory)
        onChange?()
        onLoaded?()
        schedulePartialRefreshRetryIfNeeded(for: directory, failure: partialFailure)
        resolvePendingRefresh(afterLoadGeneration: changeGeneration)
    }

    private func finishFailedLoad(loadID: Int, directory: URL, error: Error, previousDirectory: URL, previousItems: [FileItem], historyTransition: PendingHistoryTransition?, changeGeneration: Int) {
        guard isCurrentLoad(loadID) else { return }
        DiagnosticLogger.log(.error, category: "FilePane", "Directory load failed: path=\(DiagnosticLogger.sanitizedPath(directory)); reason=\(error.localizedDescription)")
        state.currentDirectory = previousDirectory
        navigation.rollBack(historyTransition)
        items = previousItems
        loadFailure = DirectoryLoadFailure(directory: directory, error: error)
        errorMessage = error.localizedDescription
        onChange?()
        resolvePendingRefresh(afterLoadGeneration: changeGeneration)
    }

    private func schedulePartialRefreshRetryIfNeeded(for directory: URL, failure: DirectoryContentsReadError?) {
        guard failure != nil, partialRefreshRetryCount < maximumPartialRefreshRetries else { return }
        partialRefreshRetryCount += 1
        let retryNumber = partialRefreshRetryCount
        loadCoordinator.scheduleRetry(directory: directory, attempt: retryNumber) { [weak self] in
            guard let self, self.currentDirectory == directory else { return }
            DiagnosticLogger.log(.info, category: "FilePane", "Retrying incomplete directory refresh: path=\(DiagnosticLogger.sanitizedPath(directory)); attempt=\(retryNumber)")
            self.loadCurrentDirectory(forceRefresh: true)
        }
        onChange?()
    }


    private func isCurrentLoad(_ loadID: Int) -> Bool {
        activeLoadID == loadID
    }


    private func resolvePendingRefresh(afterLoadGeneration loadGeneration: Int) {
        guard let pendingRefreshGeneration else { return }
        if pendingRefreshGeneration <= loadGeneration {
            // This load observed the pending generation, so its completion is
            // the corresponding refresh even when it failed or was cancelled.
            self.pendingRefreshGeneration = nil
        } else {
            startPendingExternalRefreshIfNeeded()
        }
    }


}
