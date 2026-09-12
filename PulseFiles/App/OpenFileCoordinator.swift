// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesModels
import PulseFilesServices

enum OpenFileValidationError: LocalizedError, Equatable {
    case notApplicationBundle(URL)
    case probeUnavailable(URL)

    var errorDescription: String? {
        switch self {
        case .notApplicationBundle(let url):
            return "%@ is not an application.".localized(with: url.lastPathComponent)
        case .probeUnavailable(let url):
            return "%@ could not be checked in time. Try again.".localized(with: url.lastPathComponent)
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
    private let probe: any FileSystemProbing
    private let deadline: Duration
    private let handoff: Handoff

    init(
        accessPolicy: SandboxFileAccessPolicy,
        probe: any FileSystemProbing = FileSystemProbeService(),
        deadline: Duration = .milliseconds(250),
        handoff: @escaping Handoff
    ) {
        self.accessPolicy = accessPolicy
        self.probe = probe
        self.deadline = deadline
        self.handoff = handoff
    }

    func open(_ fileURL: URL, with applicationURL: URL?) async throws {
        let urls = [fileURL] + (applicationURL.map { [$0] } ?? [])
        try await accessPolicy.withValidatedAccess(to: urls) {
            let fileAnswer = await probe.exists(fileURL, deadline: deadline)
            guard case .value(let fileExists) = fileAnswer else { throw OpenFileValidationError.probeUnavailable(fileURL) }
            guard fileExists else {
                throw FileOperationError.sourceMissing(fileURL)
            }
            if let applicationURL {
                let applicationAnswer = await probe.exists(applicationURL, deadline: deadline)
                guard case .value(let applicationExists) = applicationAnswer else { throw OpenFileValidationError.probeUnavailable(applicationURL) }
                guard applicationExists else {
                    throw FileOperationError.sourceMissing(applicationURL)
                }
                let bundleAnswer = await probe.isApplicationBundle(applicationURL, deadline: deadline)
                guard case .value(let isBundle) = bundleAnswer else { throw OpenFileValidationError.probeUnavailable(applicationURL) }
                guard isBundle else {
                    throw OpenFileValidationError.notApplicationBundle(applicationURL)
                }
            }
            handoff(fileURL, applicationURL)
        }
    }
}
