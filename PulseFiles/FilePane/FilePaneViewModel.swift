import Foundation

@MainActor
final class FilePaneViewModel {
    private let fileSystem: FileSystemServicing
    private let accessPolicy: SandboxFileAccessPolicy
    private let snapshotCache = DirectorySnapshotCache()
    private let directoryMonitor = DirectoryMonitor()
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

    var onChange: (() -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    var onDisplayPreferencesChanged: ((Bool, FileSortDescriptor) -> Void)?

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
        fileSystem: FileSystemServicing,
        accessPolicy: SandboxFileAccessPolicy = .current,
        directoryLoadTimeout: TimeInterval = 15
    ) {
        precondition(directoryLoadTimeout > 0 && directoryLoadTimeout.isFinite)
        self.fileSystem = fileSystem
        self.accessPolicy = accessPolicy
        self.directoryLoadTimeout = directoryLoadTimeout
        let validatedDirectory = accessPolicy.validatedDirectory(initialDirectory)
        state = PaneState(
            currentDirectory: validatedDirectory,
            history: NavigationHistory(initialURL: validatedDirectory),
            sort: sort,
            showsHiddenFiles: showsHiddenFiles
        )
        directoryMonitor.onChange = { [weak self] in
            guard let self else { return }
            self.reloadAfterExternalDirectoryChange()
        }
    }

    private let directoryLoadTimeout: TimeInterval

    var currentDirectory: URL { state.currentDirectory }
    /// Identifies the directory load currently represented by the pane state.
    var loadGeneration: Int { activeLoadID }
    var isAccessRestrictedToExperimentalSandbox: Bool { accessPolicy.isEnabled }
    var sortDescriptor: FileSortDescriptor { state.sort }
    var showsHiddenFiles: Bool { state.showsHiddenFiles }
    var visibleItems: [FileItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(query)
                || item.filename.localizedCaseInsensitiveContains(query)
                || item.fileExtension.localizedCaseInsensitiveContains(query)
        }
    }

    func validateAccess(to url: URL) throws {
        try accessPolicy.validateAccess(to: url)
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
            state.sort = FileSortDescriptor(key: key, ascending: true)
        }
        persistDisplayPreferences()
        applyCurrentSort()
    }

    func setSort(_ key: FileSortKey, ascending: Bool) {
        let descriptor = FileSortDescriptor(key: key, ascending: ascending)
        guard state.sort != descriptor else { return }
        state.sort = descriptor
        persistDisplayPreferences()
        applyCurrentSort()
    }

    func setSearchQuery(_ query: String) {
        guard searchQuery != query else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = query
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
        retryTask = nil
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
        // This single deadline covers snapshot metadata validation and directory
        // enumeration, including the metadata read used to cache a new listing.
        loadWatchdogTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(directoryLoadTimeout * 1_000_000_000))
            } catch {
                return
            }
            finishTimedOutLoad(
                loadID: loadID,
                directory: directory,
                previousDirectory: previousDirectory,
                previousItems: previousItems,
                changeGeneration: loadChangeGeneration
            )
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let directoryContents: DirectoryContentsResult
                if !forceRefresh, let snapshot = snapshotCache.snapshot(for: snapshotKey) {
                    let metadata = try await fileSystem.directorySnapshotMetadata(at: directory)
                    guard !Task.isCancelled else {
                        finishCancelledLoad(loadID: loadID, changeGeneration: loadChangeGeneration)
                        return
                    }
                    guard isCurrentLoad(loadID) else { return }

                    if snapshot.metadata == metadata {
                        directoryContents = DirectoryContentsResult(items: snapshot.items, itemReadFailures: [])
                        DiagnosticLogger.log(.debug, category: "FilePane", "Directory snapshot validated: path=\(DiagnosticLogger.sanitizedPath(directory)); itemCount=\(directoryContents.items.count)")
                    } else {
                        directoryContents = try await fileSystem.contentsOfDirectory(at: directory, includingHidden: includeHidden, sort: sort)
                        if directoryContents.isComplete {
                            let refreshedMetadata = try await fileSystem.directorySnapshotMetadata(at: directory)
                            snapshotCache.store(directoryContents.items, metadata: refreshedMetadata, for: snapshotKey)
                        }
                    }
                } else {
                    directoryContents = try await fileSystem.contentsOfDirectory(at: directory, includingHidden: includeHidden, sort: sort)
                    if directoryContents.isComplete {
                        let metadata = try await fileSystem.directorySnapshotMetadata(at: directory)
                        snapshotCache.store(directoryContents.items, metadata: metadata, for: snapshotKey)
                    }
                }
                guard !Task.isCancelled else {
                    finishCancelledLoad(loadID: loadID, changeGeneration: loadChangeGeneration)
                    return
                }
                guard isCurrentLoad(loadID) else { return }
                completeLoadWatchdog(for: loadID)
                DiagnosticLogger.log(.info, category: "FilePane", "Directory load completed: path=\(DiagnosticLogger.sanitizedPath(directory)); itemCount=\(directoryContents.items.count); metadataFailures=\(directoryContents.itemReadFailures.count)")
                let partialFailure = directoryContents.isComplete
                    ? nil
                    : DirectoryContentsReadError(failures: directoryContents.itemReadFailures)
                if partialFailure == nil {
                    items = directoryContents.items
                    partialRefreshFailure = nil
                    partialRefreshRetryCount = 0
                } else if directory == previousDirectory, previousListingWasComplete {
                    // A complete prior snapshot is safer than replacing the pane with
                    // a list that silently omits children.
                    items = previousItems
                    partialRefreshFailure = partialFailure
                } else {
                    // There is no prior complete listing to retain. Show the partial
                    // data explicitly, never as a fully current listing.
                    items = directoryContents.items
                    partialRefreshFailure = partialFailure
                }
                state.currentDirectory = directory
                if addToHistory && directory != previousDirectory {
                    state.history.visit(directory)
                }
                onDirectoryChanged?(directory)
                directoryMonitor.startMonitoring(directory)
                isLoading = false
                onChange?()
                onLoaded?()
                schedulePartialRefreshRetryIfNeeded(for: directory, failure: partialFailure)
                resolvePendingRefresh(afterLoadGeneration: loadChangeGeneration)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    finishCancelledLoad(loadID: loadID, changeGeneration: loadChangeGeneration)
                    return
                }
                guard isCurrentLoad(loadID) else { return }
                completeLoadWatchdog(for: loadID)
                DiagnosticLogger.log(.error, category: "FilePane", "Directory load failed: path=\(DiagnosticLogger.sanitizedPath(directory)); reason=\(error.localizedDescription)")
                state.currentDirectory = previousDirectory
                items = previousItems
                loadFailure = DirectoryLoadFailure(directory: directory, error: error)
                errorMessage = error.localizedDescription
                isLoading = false
                onChange?()
                resolvePendingRefresh(afterLoadGeneration: loadChangeGeneration)
            }
        }
    }

    private func schedulePartialRefreshRetryIfNeeded(for directory: URL, failure: DirectoryContentsReadError?) {
        guard failure != nil, partialRefreshRetryCount < maximumPartialRefreshRetries else { return }
        partialRefreshRetryCount += 1
        isPartialRefreshRetryScheduled = true
        let retryNumber = partialRefreshRetryCount
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.currentDirectory == directory else { return }
            DiagnosticLogger.log(.info, category: "FilePane", "Retrying incomplete directory refresh: path=\(DiagnosticLogger.sanitizedPath(directory)); attempt=\(retryNumber)")
            self.loadCurrentDirectory(forceRefresh: true)
        }
        onChange?()
    }

    private func isCurrentLoad(_ loadID: Int) -> Bool {
        activeLoadID == loadID
    }

    private func completeLoadWatchdog(for loadID: Int) {
        guard isCurrentLoad(loadID) else { return }
        loadWatchdogTask?.cancel()
        loadWatchdogTask = nil
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
        completeLoadWatchdog(for: loadID)
        isLoading = false
        onChange?()
        resolvePendingRefresh(afterLoadGeneration: changeGeneration)
    }
}
