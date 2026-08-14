import PulseFilesUtilities
import PulseFilesModels
import Foundation
import Darwin

/// Measures logical file content using POSIX filesystem calls rather than the
/// directory listing cache. Symbolic links are measured as links and never
/// followed while walking a directory.
package struct SystemFileSizeService {
    /// Returns the logical size in bytes of a file, or the combined logical
    /// size of every entry contained by a directory.
    package func size(of url: URL) throws -> Int64 {
        try size(atPath: url.path)
    }

    private func size(atPath path: String) throws -> Int64 {
        var status = stat()
        guard Darwin.lstat(path, &status) == 0 else { throw posixError() }

        switch status.st_mode & S_IFMT {
        case S_IFDIR:
            return try directorySize(atPath: path)
        default:
            return Int64(status.st_size)
        }
    }

    private func directorySize(atPath path: String) throws -> Int64 {
        guard let directory = Darwin.opendir(path) else { throw posixError() }
        defer { Darwin.closedir(directory) }

        var total: Int64 = 0
        while let entry = Darwin.readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }

            let childPath = (path as NSString).appendingPathComponent(name)
            let childSize = try size(atPath: childPath)
            let (sum, overflow) = total.addingReportingOverflow(childSize)
            total = overflow ? Int64.max : sum
        }
        return total
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
