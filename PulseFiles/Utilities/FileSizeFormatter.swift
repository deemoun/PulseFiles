import Foundation

enum FileSizeFormatter {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesActualByteCount = false
        return formatter
    }()

    static func string(fromByteCount byteCount: Int64) -> String {
        formatter.string(fromByteCount: byteCount)
    }
}
