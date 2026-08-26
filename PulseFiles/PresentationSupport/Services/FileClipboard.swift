// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

package final class FileClipboard {
    package enum Operation: String {
        case copy
        case move
    }

    package struct Payload: Equatable {
        package let urls: [URL]
        package let operation: Operation

        package init(urls: [URL], operation: Operation) {
            self.urls = urls
            self.operation = operation
        }
    }

    package static let operationPasteboardType = NSPasteboard.PasteboardType("com.pulsefiles.file-operation")

    private let pasteboard: NSPasteboard

    package var changeCount: Int { pasteboard.changeCount }

    package init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    package func write(urls: [URL], operation: Operation) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        pasteboard.setString(operation.rawValue, forType: Self.operationPasteboardType)
    }

    package func read() -> Payload? {
        let operation = pasteboard.string(forType: Self.operationPasteboardType)
            .flatMap(Operation.init(rawValue:)) ?? .copy
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        let urls = objects.compactMap { object -> URL? in
            if let url = object as? URL { return url }
            if let nsURL = object as? NSURL { return nsURL as URL }
            return nil
        }.filter(\.isFileURL)
        guard !urls.isEmpty else { return nil }
        return Payload(urls: urls, operation: operation)
    }
}
