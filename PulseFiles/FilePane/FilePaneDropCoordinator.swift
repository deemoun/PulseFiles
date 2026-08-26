// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

package struct DropTransferPolicy {
    enum Operation: Equatable { case copy, move }
    typealias VolumeIdentifierProvider = (URL) -> String?
    package var volumeIdentifierProvider: VolumeIdentifierProvider = { url in
        let values = try? url.resourceValues(forKeys: [.volumeURLKey])
        return (values?.allValues[.volumeURLKey] as? URL).map { $0.standardizedFileURL.path }
    }
    package func resolvedOperation(for sources: [URL], destinationDirectory: URL, isInternalAppDrag: Bool, optionForcesCopy: Bool) -> Operation {
        guard !optionForcesCopy, isInternalAppDrag, !sources.isEmpty,
              sourcesShareVolume(with: destinationDirectory, sources: sources) else { return .copy }
        return .move
    }
    package func sourcesShareVolume(with destinationDirectory: URL, sources: [URL]) -> Bool {
        guard let destinationVolume = volumeIdentifierProvider(destinationDirectory) else { return false }
        return sources.allSatisfy { volumeIdentifierProvider($0) == destinationVolume }
    }
}

/// Decodes pasteboard input and centralizes safe, non-mutating drop decisions.
package final class FilePaneDropCoordinator {
    package let transferPolicy: DropTransferPolicy
    package init(transferPolicy: DropTransferPolicy = DropTransferPolicy()) { self.transferPolicy = transferPolicy }

    package func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.compactMap {
            ($0 as? URL) ?? ($0 as? NSURL)?.absoluteURL
        } ?? []
    }

    package func operation(for sources: [URL], destination: URL, pasteboard: NSPasteboard, optionForcesCopy: Bool) -> DropTransferPolicy.Operation {
        transferPolicy.resolvedOperation(for: sources, destinationDirectory: destination,
            isInternalAppDrag: pasteboard.string(forType: .pulseFilesInternalDrag) != nil,
            optionForcesCopy: optionForcesCopy)
    }

    package static func permitsDrop(sources: [URL], destination: URL, operation: DropTransferPolicy.Operation, directoryValues: [URL: Bool]) -> Bool {
        guard directoryValues[destination] == true,
              sources.allSatisfy({ directoryValues[$0] != nil }) else { return false }
        let nested = sources.contains { source in
            directoryValues[source] == true && FilePathComparison.isSameOrDescendant(destination, ofDirectory: source)
        }
        guard !nested else { return false }
        return operation == .copy || !sources.allSatisfy { FilePathComparison.isSamePath($0.deletingLastPathComponent(), destination) }
    }
}

extension NSPasteboard.PasteboardType {
    package static let pulseFilesInternalDrag = NSPasteboard.PasteboardType("com.pulsefiles.internal-drag")
}
