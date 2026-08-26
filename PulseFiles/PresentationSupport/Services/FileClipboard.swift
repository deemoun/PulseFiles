// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

package final class FileClipboard {
    enum Operation: String {
        case copy
        case move
    }

    struct Payload: Equatable {
        let urls: [URL]
        let operation: Operation
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
