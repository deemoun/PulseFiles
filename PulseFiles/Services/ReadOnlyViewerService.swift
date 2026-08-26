// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import Foundation

package enum ViewerContentKind: Equatable {
    case text(String.Encoding)
    case hex
}

package struct ViewerSnapshot: Equatable {
    package let content: String
    package let kind: ViewerContentKind
    package let bytesRead: Int
    package let isComplete: Bool
    package let isTruncated: Bool
}

/// Incrementally reads a file while retaining a bounded prefix. The validated
/// security scope remains active until reading finishes or the stream is cancelled.
package final class ReadOnlyViewerService {
    package struct Limits: Equatable {
        var chunkSize = 64 * 1024
        var retainedByteCount = 4 * 1024 * 1024

        init(chunkSize: Int = 64 * 1024, retainedByteCount: Int = 4 * 1024 * 1024) {
            self.chunkSize = max(1, chunkSize)
            self.retainedByteCount = max(1, retainedByteCount)
        }
    }

    private let accessPolicy: SandboxFileAccessPolicy
    private let limits: Limits

    package init(accessPolicy: SandboxFileAccessPolicy = .current, limits: Limits = Limits()) {
        self.accessPolicy = accessPolicy
        self.limits = limits
    }

    package func snapshots(for url: URL) -> AsyncThrowingStream<ViewerSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [accessPolicy, limits] in
                do {
                    try accessPolicy.withValidatedAccess(to: url) {
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        var retained = Data()
                        var bytesRead = 0
                        var complete = false

                        while !Task.isCancelled {
                            let chunk = try handle.read(upToCount: limits.chunkSize) ?? Data()
                            if chunk.isEmpty {
                                complete = true
                                break
                            }
                            bytesRead += chunk.count
                            if retained.count < limits.retainedByteCount {
                                retained.append(chunk.prefix(limits.retainedByteCount - retained.count))
                            }
                            continuation.yield(Self.snapshot(data: retained, bytesRead: bytesRead, isComplete: false, isTruncated: bytesRead > retained.count))
                            if retained.count == limits.retainedByteCount {
                                // The retained prefix is the complete viewer payload; avoid
                                // scanning the remainder of a very large file unnecessarily.
                                break
                            }
                        }
                        if !Task.isCancelled {
                            continuation.yield(Self.snapshot(data: retained, bytesRead: bytesRead, isComplete: complete, isTruncated: !complete))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    package static func snapshot(data: Data, bytesRead: Int, isComplete: Bool, isTruncated: Bool) -> ViewerSnapshot {
        if let encoding = detectedTextEncoding(in: data), let string = decodedString(data, encoding: encoding) {
            return ViewerSnapshot(content: string, kind: .text(encoding), bytesRead: bytesRead, isComplete: isComplete, isTruncated: isTruncated)
        }
        return ViewerSnapshot(content: hexDump(data), kind: .hex, bytesRead: bytesRead, isComplete: isComplete, isTruncated: isTruncated)
    }

    package static func detectedTextEncoding(in data: Data) -> String.Encoding? {
        let bytes = [UInt8](data.prefix(4096))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8 }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return .utf32LittleEndian }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return .utf32BigEndian }
        if bytes.starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        if bytes.starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }
        if bytes.isEmpty { return .utf8 }
        if bytes.contains(0) {
            let evenZeroes = stride(from: 0, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
            let oddZeroes = stride(from: 1, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
            if oddZeroes > bytes.count / 4 { return .utf16LittleEndian }
            if evenZeroes > bytes.count / 4 { return .utf16BigEndian }
            return nil
        }
        let controlCount = bytes.filter { $0 < 0x20 && ![0x09, 0x0A, 0x0D].contains($0) }.count
        guard controlCount * 20 <= bytes.count else { return nil }
        if String(data: data, encoding: .utf8) != nil { return .utf8 }
        return String(data: data, encoding: .windowsCP1252) == nil ? nil : .windowsCP1252
    }

    private static func decodedString(_ data: Data, encoding: String.Encoding) -> String? {
        var payload = data
        if encoding == .utf8, payload.starts(with: [0xEF, 0xBB, 0xBF]) { payload.removeFirst(3) }
        if (encoding == .utf16LittleEndian || encoding == .utf16BigEndian), payload.count >= 2 { payload.removeFirst(2) }
        if (encoding == .utf32LittleEndian || encoding == .utf32BigEndian), payload.count >= 4 { payload.removeFirst(4) }
        return String(data: payload, encoding: encoding)
    }

    package static func hexDump(_ data: Data) -> String {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 16).map { offset in
            let line = Array(bytes[offset..<min(offset + 16, bytes.count)])
            let hex = line.map { String(format: "%02X", $0) }.joined(separator: " ").padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = line.map { (0x20...0x7E).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            return String(format: "%08X  %@  |%@|", offset, hex, ascii)
        }.joined(separator: "\n")
    }
}
