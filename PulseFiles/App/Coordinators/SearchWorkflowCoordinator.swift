import AppKit
import Foundation

@MainActor
final class SearchWorkflowCoordinator {
    private let service: any DescendantSearching
    private let accessPolicy: SandboxFileAccessPolicy
    private var task: Task<Void, Never>?
    private var resultsWindow: NSWindowController?

    init(service: any DescendantSearching, accessPolicy: SandboxFileAccessPolicy) {
        self.service = service
        self.accessPolicy = accessPolicy
    }

    func cancel() { task?.cancel() }

    func search(root: URL, text: String, completion: @escaping (Result<DescendantSearchResult, Error>) -> Void) {
        task?.cancel()
        task = Task { [service] in
            do {
                let query = DescendantSearchQuery(nameMatcher: .glob("*\(text)*"), scopes: [.folder(root, includeDescendants: true)])
                let result = try await service.search(query: query)
                guard !Task.isCancelled else { return }
                completion(.success(result))
            } catch is CancellationError {
                return
            } catch {
                completion(.failure(error))
            }
        }
    }

    func present(_ result: DescendantSearchResult, root: URL, query: String, sender: Any?, onAction: @escaping (DescendantSearchResultsViewController.Action, DescendantSearchItem) -> Void) throws {
        try accessPolicy.validateAccess(to: root)
        let controller = DescendantSearchResultsViewController()
        controller.title = "Search Results for “\(query)”"
        controller.onAction = onAction
        _ = controller.view
        controller.display(result)
        let window = NSWindow(contentViewController: controller)
        window.title = controller.title ?? "Search Results"
        window.setContentSize(NSSize(width: 760, height: 440))
        let owner = NSWindowController(window: window)
        resultsWindow = owner
        owner.showWindow(sender)
    }
}
