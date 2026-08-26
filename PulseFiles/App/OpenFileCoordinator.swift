// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import UniformTypeIdentifiers

enum OpenFileValidationError: LocalizedError, Equatable {
    case notApplicationBundle(URL)

    var errorDescription: String? {
        switch self {
        case .notApplicationBundle(let url):
            return "%@ is not an application.".localized(with: url.lastPathComponent)
        }
    }
}

/// Validates every URL involved in an open request and retains any matching
/// security-scoped grants until the request has been handed to the workspace.
/// The probes and handoff are injectable so validation can be tested without
/// asking macOS to launch another process.
struct OpenFileCoordinator {
    typealias Handoff = (_ fileURL: URL, _ applicationURL: URL?) -> Void

    private let accessPolicy: SandboxFileAccessPolicy
    private let fileExists: (URL) -> Bool
    private let isApplicationBundle: (URL) -> Bool
    private let handoff: Handoff

    init(
        accessPolicy: SandboxFileAccessPolicy,
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        isApplicationBundle: @escaping (URL) -> Bool = { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .applicationBundle) == true
        },
        handoff: @escaping Handoff
    ) {
        self.accessPolicy = accessPolicy
        self.fileExists = fileExists
        self.isApplicationBundle = isApplicationBundle
        self.handoff = handoff
    }

    func open(_ fileURL: URL, with applicationURL: URL?) throws {
        let urls = [fileURL] + (applicationURL.map { [$0] } ?? [])
        try accessPolicy.withValidatedAccess(to: urls) {
            guard fileExists(fileURL) else {
                throw FileOperationError.sourceMissing(fileURL)
            }
            if let applicationURL {
                guard fileExists(applicationURL) else {
                    throw FileOperationError.sourceMissing(applicationURL)
                }
                guard isApplicationBundle(applicationURL) else {
                    throw OpenFileValidationError.notApplicationBundle(applicationURL)
                }
            }
            handoff(fileURL, applicationURL)
        }
    }
}
