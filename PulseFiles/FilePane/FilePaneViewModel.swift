import Foundation

@MainActor
final class FilePaneViewModel {
    private let fileSystem: FileSystemServicing
    private let accessPolicy: SandboxFileAccessPolicy
    private let snapshotCache = DirectorySnapshotCache()
    private let directoryMonitor: DirectoryMonitor
    private var loadTask: Task<Void, Never>?
    private var loadWatchdogTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var partialRefreshRetryCount = 0
    private let maximumPartialRefreshRetries = 2
    private var nextLoadID = 0
    private var activeLoadID = 0
    /// Monotonically increases for each filesystem notification received for the
    /// displayed directory. A load records the value it started with so an event
    /// that arrives while it is running cannot be lost.
    private var directoryChangeGeneration = 0
    private var pendingRefreshGeneration: Int?
    private var nextRetryID = 0
    private var activeRetryID = 0

    private(set) var state: PaneState
    private(set) var items: [FileItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadFailure: DirectoryLoadFailure?
    /// Non-nil when a directory enumeration omitted children because their metadata
    /// could not be read. The visible items are not a confirmed-current snapshot.
    private(set) var partialRefreshFailure: DirectoryContentsReadError?
    private(set) var isPartialRefreshRetryScheduled = false
    private(set) var searchQuery = ""
    private(set) var quickSearchMatchMode: QuickSearchMatchMode
    private(set) var quickSearchPresentation: QuickSearchPresentation

    var onChange: (() -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    var onDisplayPreferencesChanged: ((Bool, FileSortDescriptor) -> Void)?
    var onTabsChanged: (() -> Void)?

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

    init(
        initialDirectory: URL,
        showsHiddenFiles: Bool = false,
        sort: FileSortDescriptor = FileSortDescriptor(),
        restoration: PaneRestorationState? = nil,
        fileSystem: FileSystemServicing,
        accessPolicy: SandboxFileAccessPolicy = .current,
        directoryLoadTimeout: TimeInterval = 15,
        directoryMonitor: DirectoryMonitor = DirectoryMonitor(),
        quickSearchMatchMode: QuickSearchMatchMode = .contains,
        quickSearchPresentation: QuickSearchPresentation = .filterMatches
    ) {
        precondition(directoryLoadTimeout > 0 && directoryLoadTimeout.isFinite)
        self.fileSystem = fileSystem
        self.accessPolicy = accessPolicy
        self.directoryMonitor = directoryMonitor
        self.quickSearchMatchMode = quickSearchMatchMode
        self.quickSearchPresentation = quickSearchPresentation
        self.directoryLoadTimeout = directoryLoadTimeout
        let validatedDirectory = accessPolicy.validatedDirectory(initialDirectory)
        let restoredTabs = restoration?.tabs.compactMap { saved -> PaneTabState? in
            guard accessPolicy.canAccess(saved.directory),
                  (try? saved.directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let directory = saved.directory.standardizedFileURL
            return PaneTabState(id: saved.id, currentDirectory: directory, history: NavigationHistory(initialURL: directory), sort: saved.sort, showsHiddenFiles: saved.showsHiddenFiles)
        } ?? []
        if restoredTabs.isEmpty {
            state = PaneState(currentDirectory: validatedDirectory, history: NavigationHistory(initialURL: validatedDirectory), sort: sort, showsHiddenFiles: showsHiddenFiles)
        } else {
            state = PaneState(tabs: restoredTabs, activeTabID: restoration?.activeTabID)
        }
        directoryMonitor.onChange = { [weak self] in
            guard let self else { return }
            self.reloadAfterExternalDirectoryChange()
        }
    }

    deinit {
        loadTask?.cancel()
        loadWatchdogTask?.cancel()
        retryTask?.cancel()
        loadTask = nil
        loadWatchdogTask = nil
        retryTask = nil
        activeRetryID = 0
        onChange = nil
        onDirectoryChanged = nil
        onDisplayPreferencesChanged = nil
        directoryMonitor.onChange = nil
        directoryMonitor.stop()
    }

    private let directoryLoadTimeout: TimeInterval

    var currentDirectory: URL { state.currentDirectory }
    /// Identifies the directory load currently represented by the pane state.
    var loadGeneration: Int { activeLoadID }
    var isAccessRestrictedToExperimentalSandbox: Bool { accessPolicy.isEnabled }
    var sortDescriptor: FileSortDescriptor { state.sort }
    var showsHiddenFiles: Bool { state.showsHiddenFiles }
    var focusedURL: URL? { state.focusedURL }
    var backDestination: URL? { state.history.backStack.last }
    var navigationHistory: NavigationHistory { state.history }
    var tabs: [PaneTabState] { state.tabs }
    var activeTabID: UUID { state.activeTabID }
    var visibleItems: [FileItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        guard quickSearchPresentation == .filterMatches else { return items }
        return items.filter { match(for: $0) != nil }
    }

    func match(for item: FileItem) -> QuickSearchMatch? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        return QuickSearchMatcher.match(query, in: item.filename, mode: quickSearchMatchMode)
    }

    func setQuickSearchOptions(matchMode: QuickSearchMatchMode, presentation: QuickSearchPresentation) {
        guard quickSearchMatchMode != matchMode || quickSearchPresentation != presentation else { return }
        quickSearchMatchMode = matchMode
        quickSearchPresentation = presentation
        onChange?()
    }

    func validateAccess(to url: URL) throws {
        try accessPolicy.validateAccess(to: url)
    }

    /// Captures only logical browser state, allowing panes to exchange state
    /// without exchanging their controller/view instances.
    func logicalStateSnapshot() -> PaneState {
        var snapshot = state
        snapshot.searchQuery = searchQuery
        return snapshot
    }

    func setFocusedURL(_ url: URL?) {
        state.setFocus(url)
    }

    func setMarkedURLs(_ urls: Set<URL>) {
        state.markedURLs = urls
    }

    /// Restores a snapshot atomically after its destination passes the same
    /// sandbox policy used by ordinary navigation.
    func restoreLogicalState(_ snapshot: PaneState, onLoaded: (() -> Void)? = nil) throws {
        try snapshot.tabs.forEach { try accessPolicy.validateAccess(to: $0.currentDirectory) }
        var restored = snapshot
        restored.currentDirectory = snapshot.currentDirectory.standardizedFileURL
        state = restored
        searchQuery = restored.searchQuery
        load(directory: restored.currentDirectory, addToHistory: false, forceRefresh: false, onLoaded: onLoaded)
        onTabsChanged?()
    }

    @discardableResult
    func newTab(directory: URL? = nil) -> UUID {
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
    func closeTab(id: UUID? = nil) -> Bool {
        guard state.tabs.count > 1,
              let index = state.tabs.firstIndex(where: { $0.id == (id ?? state.activeTabID) }) else { return false }
        let wasActive = state.tabs[index].id == state.activeTabID
        state.tabs.remove(at: index)
        if wasActive {
            state.activeTabID = state.tabs[min(index, state.tabs.count - 1)].id
            activateCurrentTab()
        }
        onTabsChanged?()
        return true
    }

    func selectTab(id: UUID) {
        guard id != state.activeTabID, state.tabs.contains(where: { $0.id == id }) else { return }
        state.searchQuery = searchQuery
        state.activeTabID = id
        activateCurrentTab()
        onTabsChanged?()
    }

    func selectNextTab() { selectRelativeTab(offset: 1) }
    func selectPreviousTab() { selectRelativeTab(offset: -1) }

    @discardableResult
    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
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
    func canNavigate(to directory: URL) -> Bool {
        accessPolicy.canAccess(directory)
    }

    func loadCurrentDirectory(forceRefresh: Bool = false, onLoaded: (() -> Void)? = nil) {
        load(directory: state.currentDirectory, addToHistory: false, forceRefresh: forceRefresh, onLoaded: onLoaded)
    }

    func retryFailedDirectoryLoad() {
        guard loadFailure?.isRetryable == true else { return }
        load(directory: state.currentDirectory, addToHistory: false, forceRefresh: true)
    }

    func reloadAfterExternalDirectoryChange() {
        snapshotCache.invalidate(directory: state.currentDirectory)
        directoryChangeGeneration += 1
        pendingRefreshGeneration = directoryChangeGeneration
        startPendingExternalRefreshIfNeeded()
    }

    func invalidateCurrentDirectorySnapshot() {
        snapshotCache.invalidate(directory: state.currentDirectory)
    }

    func navigate(to url: URL) {
        let validatedURL = accessPolicy.validatedDirectory(url, fallback: state.currentDirectory)
        if validatedURL != url {
            DiagnosticLogger.log(.warning, category: "FilePane", "Rejected navigation outside sandbox: requested=\(DiagnosticLogger.sanitizedPath(url)); redirected=\(DiagnosticLogger.sanitizedPath(validatedURL))")
        }
        load(directory: validatedURL, addToHistory: true)
    }

    /// Leaves a directory whose volume was removed before a stale file descriptor can
    /// generate further directory events. The fallback is always policy-validated.
    @discardableResult
    func fallBackIfCurrentDirectoryIsUnavailable(
        directoryExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        preferredFallback: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        guard !directoryExists(state.currentDirectory) else { return false }
        directoryMonitor.stop()
        loadTask?.cancel()
        loadWatchdogTask?.cancel()
        retryTask?.cancel()
        loadTask = nil
        loadWatchdogTask = nil
        retryTask = nil
        activeRetryID = 0
        let fallback = accessPolicy.validatedDirectory(preferredFallback, fallback: accessPolicy.rootURL)
        items = []
        searchQuery = ""
        state.currentDirectory = fallback
        state.history.visit(fallback)
        load(directory: fallback, addToHistory: false)
        return true
    }

    func goParent() {
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

    func navigateToSandboxRoot() {
        navigate(to: accessPolicy.validatedDirectory(ExperimentalFlags.appSandboxRoot))
    }

    func navigateToParentOfFailedDirectory() {
        guard let failedDirectory = loadFailure?.directory else { return }
        let parent = failedDirectory.deletingLastPathComponent()
        guard parent != failedDirectory else { return }
        navigate(to: accessPolicy.validatedDirectory(parent, fallback: state.currentDirectory))
    }

    func goBack() {
        guard let url = state.history.goBack() else { return }
        load(directory: url, addToHistory: false)
    }

    func goForward() {
        guard let url = state.history.goForward() else { return }
        load(directory: url, addToHistory: false)
    }

    func toggleHiddenFiles() {
        setShowsHiddenFiles(!state.showsHiddenFiles)
    }

    func setShowsHiddenFiles(_ showsHiddenFiles: Bool) {
        guard state.showsHiddenFiles != showsHiddenFiles else { return }
        state.showsHiddenFiles = showsHiddenFiles
        persistDisplayPreferences()
        loadCurrentDirectory()
    }

    func setSort(_ key: FileSortKey) {
        if state.sort.key == key {
            state.sort.ascending.toggle()
        } else {
            state.sort.key = key
            state.sort.ascending = true
        }
        persistDisplayPreferences()
        applyCurrentSort()
    }

    func setSort(_ key: FileSortKey, ascending: Bool) {
        var descriptor = state.sort
        descriptor.key = key
        descriptor.ascending = ascending
        guard state.sort != descriptor else { return }
        state.sort = descriptor
        persistDisplayPreferences()
        applyCurrentSort()
    }

    func setSortDescriptor(_ descriptor: FileSortDescriptor) {
        guard state.sort != descriptor else { return }
        state.sort = descriptor
        persistDisplayPreferences()
        applyCurrentSort()
    }

    func setSearchQuery(_ query: String) {
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
        forceRefresh: Bool = false,
        changeGeneration: Int? = nil,
        onLoaded: (() -> Void)? = nil
    ) {
        loadTask?.cancel()
        loadWatchdogTask?.cancel()
        retryTask?.cancel()
        loadTask = nil
        loadWatchdogTask = nil
        retryTask = nil
        activeRetryID = 0
        isPartialRefreshRetryScheduled = false
        nextLoadID += 1
        let loadID = nextLoadID
        activeLoadID = loadID
        let loadChangeGeneration = changeGeneration ?? directoryChangeGeneration
        DiagnosticLogger.log(.info, category: "FilePane", "Directory load started: path=\(DiagnosticLogger.sanitizedPath(directory)); includeHidden=\(state.showsHiddenFiles); sort=\(state.sort.key.rawValue); ascending=\(state.sort.ascending)")
        isLoading = true
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
        let snapshotKey = DirectorySnapshotCache.Key(directory: directory, includesHiddenFiles: includeHidden, sort: sort)
        let fileSystem = fileSystem
        let accessPolicy = accessPolicy
        let snapshotCache = snapshotCache
        let timeout = directoryLoadTimeout

        // These tasks deliberately capture only immutable load inputs and service
        // dependencies. In particular, they must not keep the pane alive while a
        // filesystem implementation is blocked or ignores cancellation.
        loadWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.finishTimedOutLoad(
                    loadID: loadID,
                    directory: directory,
                    previousDirectory: previousDirectory,
                    previousItems: previousItems,
                    changeGeneration: loadChangeGeneration
                )
            }
        }
        loadTask = Task { [weak self] in
            do {
                let directoryContents = try await Self.readDirectoryContents(
                    directory: directory,
                    includeHidden: includeHidden,
                    sort: sort,
                    forceRefresh: forceRefresh,
                    snapshotKey: snapshotKey,
                    fileSystem: fileSystem,
                    accessPolicy: accessPolicy,
                    snapshotCache: snapshotCache
                )
                guard !Task.isCancelled else {
                    await MainActor.run { [weak self] in
                        self?.finishCancelledLoad(loadID: loadID, changeGeneration: loadChangeGeneration)
                    }
                    return
                }
                await MainActor.run { [weak self] in
                    self?.finishSuccessfulLoad(
                        loadID: loadID,
                        directory: directory,
                        directoryContents: directoryContents,
                        previousDirectory: previousDirectory,
                        previousItems: previousItems,
                        previousListingWasComplete: previousListingWasComplete,
                        addToHistory: addToHistory,
                        changeGeneration: loadChangeGeneration,
                        onLoaded: onLoaded
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    if error is CancellationError || Task.isCancelled {
                        self?.finishCancelledLoad(loadID: loadID, changeGeneration: loadChangeGeneration)
                    } else {
                        self?.finishFailedLoad(
                            loadID: loadID,
                            directory: directory,
                            error: error,
                            previousDirectory: previousDirectory,
                            previousItems: previousItems,
                            changeGeneration: loadChangeGeneration
                        )
                    }
                }
            }
        }
    }

    private static func readDirectoryContents(
        directory: URL,
        includeHidden: Bool,
        sort: FileSortDescriptor,
        forceRefresh: Bool,
        snapshotKey: DirectorySnapshotCache.Key,
        fileSystem: FileSystemServicing,
        accessPolicy: SandboxFileAccessPolicy,
        snapshotCache: DirectorySnapshotCache
    ) async throws -> DirectoryContentsResult {
        if !forceRefresh, let snapshot = snapshotCache.snapshot(for: snapshotKey) {
            let metadata = try await accessPolicy.withValidatedAccess(to: directory) {
                try await fileSystem.directorySnapshotMetadata(at: directory)
            }
            if snapshot.metadata == metadata {
                return DirectoryContentsResult(items: snapshot.items, itemReadFailures: [])
            }
        }

        let directoryContents = try await accessPolicy.withValidatedAccess(to: directory) {
            try await fileSystem.contentsOfDirectory(at: directory, includingHidden: includeHidden, sort: sort)
        }
        if directoryContents.isComplete {
            let metadata = try await accessPolicy.withValidatedAccess(to: directory) {
                try await fileSystem.directorySnapshotMetadata(at: directory)
            }
            snapshotCache.store(directoryContents.items, metadata: metadata, for: snapshotKey)
        }
        return directoryContents
    }

    private func finishSuccessfulLoad(
        loadID: Int,
        directory: URL,
        directoryContents: DirectoryContentsResult,
        previousDirectory: URL,
        previousItems: [FileItem],
        previousListingWasComplete: Bool,
        addToHistory: Bool,
        changeGeneration: Int,
        onLoaded: (() -> Void)?
    ) {
        guard isCurrentLoad(loadID) else { return }
        completeLoadTasks(for: loadID)
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
        state.currentDirectory = directory
        if addToHistory && directory != previousDirectory { state.history.visit(directory) }
        onDirectoryChanged?(directory)
        onTabsChanged?()
        directoryMonitor.startMonitoring(directory)
        isLoading = false
        onChange?()
        onLoaded?()
        schedulePartialRefreshRetryIfNeeded(for: directory, failure: partialFailure)
        resolvePendingRefresh(afterLoadGeneration: changeGeneration)
    }

    private func finishFailedLoad(loadID: Int, directory: URL, error: Error, previousDirectory: URL, previousItems: [FileItem], changeGeneration: Int) {
        guard isCurrentLoad(loadID) else { return }
        completeLoadTasks(for: loadID)
        DiagnosticLogger.log(.error, category: "FilePane", "Directory load failed: path=\(DiagnosticLogger.sanitizedPath(directory)); reason=\(error.localizedDescription)")
        state.currentDirectory = previousDirectory
        items = previousItems
        loadFailure = DirectoryLoadFailure(directory: directory, error: error)
        errorMessage = error.localizedDescription
        isLoading = false
        onChange?()
        resolvePendingRefresh(afterLoadGeneration: changeGeneration)
    }

    private func schedulePartialRefreshRetryIfNeeded(for directory: URL, failure: DirectoryContentsReadError?) {
        guard failure != nil, partialRefreshRetryCount < maximumPartialRefreshRetries else { return }
        partialRefreshRetryCount += 1
        isPartialRefreshRetryScheduled = true
        let retryNumber = partialRefreshRetryCount
        nextRetryID += 1
        let retryID = nextRetryID
        activeRetryID = retryID
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.runPartialRefreshRetry(
                    retryID: retryID,
                    directory: directory,
                    retryNumber: retryNumber
                )
            }
        }
        onChange?()
    }

    private func runPartialRefreshRetry(retryID: Int, directory: URL, retryNumber: Int) {
        guard activeRetryID == retryID, currentDirectory == directory else { return }
        retryTask = nil
        activeRetryID = 0
        isPartialRefreshRetryScheduled = false
        DiagnosticLogger.log(.info, category: "FilePane", "Retrying incomplete directory refresh: path=\(DiagnosticLogger.sanitizedPath(directory)); attempt=\(retryNumber)")
        loadCurrentDirectory(forceRefresh: true)
    }

    private func isCurrentLoad(_ loadID: Int) -> Bool {
        activeLoadID == loadID
    }

    private func completeLoadTasks(for loadID: Int) {
        guard isCurrentLoad(loadID) else { return }
        loadWatchdogTask?.cancel()
        loadWatchdogTask = nil
        loadTask = nil
    }

    private func finishTimedOutLoad(
        loadID: Int,
        directory: URL,
        previousDirectory: URL,
        previousItems: [FileItem],
        changeGeneration: Int
    ) {
        guard isCurrentLoad(loadID) else { return }
        DiagnosticLogger.log(.error, category: "FilePane", "Directory load timed out: path=\(DiagnosticLogger.sanitizedPath(directory)); timeout=\(directoryLoadTimeout)s")
        // Invalidate this load before cancelling it. A filesystem implementation
        // may not cooperate with cancellation, so its eventual result must never
        // replace this failure or a newer navigation result.
        activeLoadID = 0
        loadTask?.cancel()
        loadTask = nil
        loadWatchdogTask = nil
        state.currentDirectory = previousDirectory
        items = previousItems
        let timeoutError = DirectoryLoadTimeoutError(timeout: directoryLoadTimeout)
        loadFailure = DirectoryLoadFailure(directory: directory, error: timeoutError)
        errorMessage = timeoutError.localizedDescription
        isLoading = false
        onChange?()
        resolvePendingRefresh(afterLoadGeneration: changeGeneration)
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

    private func finishCancelledLoad(loadID: Int, changeGeneration: Int) {
        guard isCurrentLoad(loadID) else { return }
        completeLoadTasks(for: loadID)
        isLoading = false
        onChange?()
        resolvePendingRefresh(afterLoadGeneration: changeGeneration)
    }
}
