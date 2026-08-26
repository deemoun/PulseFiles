// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

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

    func prompt(root: URL, presenter: any WorkflowWindowProviding & WorkflowAlertPresenting,
                onAction: @escaping (DescendantSearchResultsViewController.Action, DescendantSearchItem) -> Void) {
        let alert = NSAlert(); alert.messageText = "Search This Folder".localized
        alert.informativeText = "Searches descendants of %@ without following symbolic links. Results are limited for safety.".localized(with: root.path)
        alert.addButton(withTitle: "Search".localized); alert.addButton(withTitle: "Cancel".localized)
        let field = NSTextField(string: ""); field.placeholderString = "Filename contains".localized
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 24); alert.accessoryView = field
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }; let query = field.stringValue
            self?.search(root: root, text: query) { result in
                do {
                    let value = try result.get()
                    try self?.present(value, root: root, query: query, sender: presenter, onAction: onAction)
                } catch { presenter.workflowFailed(message: "Could Not Search Folder".localized, detail: error.localizedDescription) }
            }
        }
        if let window = presenter.workflowWindow { alert.beginSheetModal(for: window, completionHandler: completion) } else { completion(alert.runModal()) }
    }

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

    func route(_ action: DescendantSearchResultsViewController.Action, item: DescendantSearchItem, root: URL) throws -> URL {
        try accessPolicy.validateAccess(to: root); try accessPolicy.validateAccess(to: item.url)
        let command: SearchResultAction = action == .open ? .open : (action == .reveal ? .reveal : .navigate)
        let route = SearchResultActionRouter().route(command, item: item, root: root,
            canAccess: { accessPolicy.canAccess($0, logDecision: false) }, fileExists: FileManager.default.fileExists(atPath:))
        guard case .perform(_, let destination) = route else { throw SearchResultRoutingError.staleResult }
        return destination
    }

    enum SearchResultRoutingError: LocalizedError {
        case staleResult
        var errorDescription: String? { "The result moved, was removed, or is no longer inside the search scope.".localized }
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
