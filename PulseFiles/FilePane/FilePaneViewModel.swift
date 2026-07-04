import Foundation

@MainActor
final class FilePaneViewModel {
    private let fileSystem: FileSystemServicing
    private let accessPolicy: SandboxFileAccessPolicy
    private var loadTask: Task<Void, Never>?

    private(set) var state: PaneState
    private(set) var items: [FileItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var onChange: (() -> Void)?
    var onDirectoryChanged: ((URL) -> Void)?

    init(initialDirectory: URL, fileSystem: FileSystemServicing, accessPolicy: SandboxFileAccessPolicy = .current) {
        self.fileSystem = fileSystem
        self.accessPolicy = accessPolicy
        let validatedDirectory = accessPolicy.validatedDirectory(initialDirectory)
        state = PaneState(currentDirectory: validatedDirectory, history: NavigationHistory(initialURL: validatedDirectory))
    }

    var currentDirectory: URL { state.currentDirectory }
    var sortDescriptor: FileSortDescriptor { state.sort }
    var showsHiddenFiles: Bool { state.showsHiddenFiles }

    func loadCurrentDirectory() {
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
        state.showsHiddenFiles.toggle()
        loadCurrentDirectory()
    }

    func setSort(_ key: FileSortKey) {
        if state.sort.key == key {
            state.sort.ascending.toggle()
        } else {
            state.sort = FileSortDescriptor(key: key, ascending: true)
        }
        items = FileSystemService.sorted(items, descriptor: state.sort)
        onChange?()
    }

    private func load(directory: URL, addToHistory: Bool) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        onChange?()

        if addToHistory {
            state.history.visit(directory)
        }
        state.currentDirectory = directory
        onDirectoryChanged?(directory)

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
            } catch {
                guard !Task.isCancelled else { return }
                items = []
                errorMessage = error.localizedDescription
                isLoading = false
                onChange?()
            }
        }
    }
}
