import Foundation

@MainActor
final class FilePaneViewModel {
    private let fileSystem: FileSystemServicing
    private let accessPolicy: SandboxFileAccessPolicy
    private let directoryMonitor = DirectoryMonitor()
    private var loadTask: Task<Void, Never>?

    private(set) var state: PaneState
    private(set) var items: [FileItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var searchQuery = ""

    var onChange: (() -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?
    var onDisplayPreferencesChanged: ((Bool, FileSortDescriptor) -> Void)?

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

    func loadCurrentDirectory(onLoaded: (() -> Void)? = nil) {
        load(directory: state.currentDirectory, addToHistory: false, onLoaded: onLoaded)
    }

    private func reloadAfterExternalDirectoryChange() {
        guard !isLoading else { return }
        load(directory: state.currentDirectory, addToHistory: false)
    }

    func navigate(to url: URL) {
        load(directory: accessPolicy.validatedDirectory(url), addToHistory: true)
    }

    func goParent() {
        let parent = state.currentDirectory.deletingLastPathComponent()
        guard parent != state.currentDirectory else { return }
        guard accessPolicy.canAccess(parent) else { return }
        navigate(to: parent)
    }

    func goBack() {
        guard let url = state.history.goBack() else { return }
        state.currentDirectory = url
        load(directory: url, addToHistory: false)
    }

    func goForward() {
        guard let url = state.history.goForward() else { return }
        state.currentDirectory = url
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
        searchQuery = query
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
        isLoading = true
        errorMessage = nil
        onChange?()

        if addToHistory {
            state.history.visit(directory)
        }
        state.currentDirectory = directory
        onDirectoryChanged?(directory)
        directoryMonitor.startMonitoring(directory)

        let includeHidden = state.showsHiddenFiles
        let sort = state.sort
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedItems = try await fileSystem.contentsOfDirectory(at: directory, includingHidden: includeHidden, sort: sort)
                guard !Task.isCancelled else { return }
                items = loadedItems
                isLoading = false
                onChange?()
                onLoaded?()
            } catch {
                guard !Task.isCancelled else { return }
                items = []
                errorMessage = error.localizedDescription
                isLoading = false
                onChange?()
                onLoaded?()
            }
        }
    }
}
