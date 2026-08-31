// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Owns file-operation presentation models. The window supplies only the host
/// and typed completion closures; this type has no pane/sidebar/settings/terminal
/// knowledge and cannot mutate the filesystem.
@MainActor
final class FileOperationPresentationCoordinator {
    struct AlertDescriptor {
        let style: NSAlert.Style
        let message: String
        let detail: String
        let buttons: [String]

        func makeAlert() -> NSAlert {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = message
            alert.informativeText = detail
            buttons.forEach { alert.addButton(withTitle: $0) }
            return alert
        }
    }

    func confirmation(operationName: String, urls: [URL], destinationDirectory: URL?, confirmButtonTitle: String) -> AlertDescriptor {
        let itemLabel = urls.count == 1 ? "Item".localized : "%d Items".localized(with: urls.count)
        return .init(
            style: .warning,
            message: "%@ %@?".localized(with: operationName, itemLabel),
            detail: confirmationSummary(operationName: operationName, urls: urls, destinationDirectory: destinationDirectory),
            buttons: [confirmButtonTitle, "Cancel — Do Not Start".localized]
        )
    }

    func conflict(destination: URL, operationName: String, fileExists: (URL) -> Bool) -> (AlertDescriptor, URL) {
        let keepBoth = FileOperationService.keepBothDestination(for: destination, fileExists: fileExists)
        return (
            .init(
                style: .warning,
                message: "An Item With This Name Already Exists".localized,
                detail: "%@ already exists in %@. Keep Both will save the incoming item as %@ during this %@ operation.".localized(
                    with: destination.lastPathComponent, destination.deletingLastPathComponent().path,
                    keepBoth.lastPathComponent, operationName
                ),
                buttons: ["Keep Both — Use New Name".localized, "Replace Existing Item".localized, "Skip This Item".localized, "Cancel Whole Operation".localized]
            ),
            keepBoth
        )
    }

    func result(_ result: FileOperationResult, operationName: String) -> AlertDescriptor? {
        guard let value = FileOperationCoordinator.resultPresentation(result, operationName: operationName) else { return nil }
        return .init(style: value.style, message: value.message, detail: value.detail, buttons: ["OK".localized])
    }

    func exportDiagnostics(
        to destination: URL,
        exporter: any DiagnosticsExporting,
        entries: [DiagnosticLogEntry],
        operationSummaries: [DiagnosticOperationSummary],
        reveal: ([URL]) -> Void
    ) throws {
        let bundle = try exporter.export(to: destination, entries: entries, operationSummaries: operationSummaries)
        reveal([bundle])
    }

    private func confirmationSummary(operationName: String, urls: [URL], destinationDirectory: URL?) -> String {
        let itemLabel = urls.count == 1 ? "1 item".localized : "%d items".localized(with: urls.count)
        var lines = ["Operation: %@".localized(with: operationName), "%@ %@:".localized(with: operationName, itemLabel)]
        let names = urls.prefix(8).map { "- \($0.lastPathComponent)" }
        lines.append(contentsOf: names)
        if urls.count > names.count { lines.append("- ...and %d more".localized(with: urls.count - names.count)) }
        let volumes = Dictionary(grouping: urls, by: { VolumeStatusPresentation.resolveSynchronously(for: $0).locationDescription }).keys.sorted()
        if !volumes.isEmpty { lines += ["", "Source volume%@: %@".localized(with: volumes.count == 1 ? "" : "s", volumes.joined(separator: ", "))] }
        if let destinationDirectory {
            lines += ["", "Destination: %@".localized(with: destinationDirectory.path), "Destination volume: %@".localized(with: VolumeStatusPresentation.resolveSynchronously(for: destinationDirectory).locationDescription)]
        }
        return lines.joined(separator: "\n")
    }
}
