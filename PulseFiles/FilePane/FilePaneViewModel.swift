import Foundation

@MainActor
final class FilePaneViewModel {
    private let fileSystem: FileSystemServicing
    private let accessPolicy: SandboxFileAccessPolicy
    private let directoryMonitor = DirectoryMonitor()
    private var loadTask: Task<Void, Never>?
    private var nextLoadID = 0
    private var activeLoadID = 0

    private(set) var state: PaneState
    private(set) var items: [FileItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadFailure: DirectoryLoadFailure?
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
    }

    init(
        initialDirectory: URL,
        showsHiddenFiles: Bool = false,
        sort: FileSortDescriptor = FileSortDescriptor(),
        fileSystem: FileSystemServicing,
        accessPolicy: SandboxFileAccessPolicy = .current
    ) {
        self.fileSystem = fileSystem
        self.accessPolicy = accessPolicy
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

    var currentDirectory: URL { state.currentDirectory }
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

    func loadCurrentDirectory(onLoaded: (() -> Void)? = nil) {
        load(directory: state.currentDirectory, addToHistory: false, onLoaded: onLoaded)
    }

    private func reloadAfterExternalDirectoryChange() {
        guard !isLoading else { return }
        load(directory: state.currentDirectory, addToHistory: false)
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

    private func load(directory: URL, addToHistory: Bool, onLoaded: (() -> Void)? = nil) {
        loadTask?.cancel()
        nextLoadID += 1
        let loadID = nextLoadID
        activeLoadID = loadID
        DiagnosticLogger.log(.info, category: "FilePane", "Directory load started: path=\(DiagnosticLogger.sanitizedPath(directory)); includeHidden=\(state.showsHiddenFiles); sort=\(state.sort.key.rawValue); ascending=\(state.sort.ascending)")
        isLoading = true
        errorMessage = nil
        loadFailure = nil
        onChange?()

        let previousDirectory = state.currentDirectory
        let previousItems = items

        let includeHidden = state.showsHiddenFiles
        let sort = state.sort
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedItems = try await fileSystem.contentsOfDirectory(at: directory, includingHidden: includeHidden, sort: sort)
                guard !Task.isCancelled else {
                    finishCancelledLoad(loadID: loadID)
                    return
                }
                guard isCurrentLoad(loadID) else { return }
                DiagnosticLogger.log(.info, category: "FilePane", "Directory load succeeded: path=\(DiagnosticLogger.sanitizedPath(directory)); itemCount=\(loadedItems.count)")
                items = loadedItems
                state.currentDirectory = directory
                if addToHistory && directory != previousDirectory {
                    state.history.visit(directory)
                }
                onDirectoryChanged?(directory)
                directoryMonitor.startMonitoring(directory)
                isLoading = false
                onChange?()
                onLoaded?()
            } catch {
                if error is CancellationError || Task.isCancelled {
                    finishCancelledLoad(loadID: loadID)
                    return
                }
                guard isCurrentLoad(loadID) else { return }
                DiagnosticLogger.log(.error, category: "FilePane", "Directory load failed: path=\(DiagnosticLogger.sanitizedPath(directory)); reason=\(error.localizedDescription)")
                state.currentDirectory = previousDirectory
                items = previousItems
                loadFailure = DirectoryLoadFailure(directory: directory, error: error)
                errorMessage = error.localizedDescription
                isLoading = false
                onChange?()
                onLoaded?()
            }
        }
    }

    private func isCurrentLoad(_ loadID: Int) -> Bool {
        activeLoadID == loadID
    }

    private func finishCancelledLoad(loadID: Int) {
        guard isCurrentLoad(loadID) else { return }
        isLoading = false
        onChange?()
    }
}
