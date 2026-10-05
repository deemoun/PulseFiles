// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesCapabilities

/// Converts deadline-bound probe answers into conservative presentation decisions.
/// An unavailable path is never treated as an existing rename target or a file
/// that is safe to open.
package struct FileSystemProbeDecisionCoordinator {
    package enum SymbolicLinkDestination: Equatable { case directory(URL), file(URL), unavailable }

    package static func inlineRenameItemExists(_ answer: FileSystemProbeAnswer<Bool>) -> Bool {
        answer == .value(true)
    }

    package static func symbolicLinkDestination(
        target: URL,
        directoryAnswer: FileSystemProbeAnswer<Bool>
    ) -> SymbolicLinkDestination {
        switch directoryAnswer {
        case .value(true): return .directory(target)
        case .value(false): return .file(target)
        case .unavailable: return .unavailable
        }
    }

    package static func conflictCandidateIsOccupied(_ answer: FileSystemProbeAnswer<Bool>) -> Bool {
        // Do not select a possibly occupied name when the filesystem missed its deadline.
        answer != .value(false)
    }

    private let probe: any FileSystemProbing

    package init(probe: any FileSystemProbing) { self.probe = probe }

    package func keepBothDestination(for destination: URL) async -> URL? {
        let ext = destination.pathExtension
        let base = ext.isEmpty ? destination.lastPathComponent : destination.deletingPathExtension().lastPathComponent
        for index in 1...10_000 {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            let candidate = destination.deletingLastPathComponent().appendingPathComponent(name)
            let answer = await probe.exists(candidate, deadline: .milliseconds(250))
            switch answer {
            case .value(false): return candidate
            case .value(true): continue
            case .unavailable: return nil
            }
        }
        return nil
    }
}
