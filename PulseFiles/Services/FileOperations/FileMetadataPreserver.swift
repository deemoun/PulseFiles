import PulseFilesUtilities
import PulseFilesModels
import Foundation
#if os(macOS)
import Darwin
#endif

/// Preserves timestamps, Finder labels/tags, extended attributes, and ACLs
/// after content transfer. Metadata loss is returned as a cleanup warning.
package final class FileMetadataPreserver {
    private let attributes: (String) throws -> [FileAttributeKey: Any]
    private let setAttributes: ([FileAttributeKey: Any], String) throws -> Void

    package init(
        fileManager: FileOperationFileManaging,
        attributes: @escaping (String) throws -> [FileAttributeKey: Any] = FileManager.default.attributesOfItem,
        setAttributes: @escaping ([FileAttributeKey: Any], String) throws -> Void = { try FileManager.default.setAttributes($0, ofItemAtPath: $1) }
    ) {
        _ = fileManager
        self.attributes = attributes
        self.setAttributes = setAttributes
    }

    package func preserve(from source: URL, to destination: URL) -> [FileOperationCleanupWarning] {
        var warnings: [FileOperationCleanupWarning] = []
        do {
            let selected = try attributes(source.path).filter { [.posixPermissions, .ownerAccountID, .groupOwnerAccountID, .creationDate, .modificationDate].contains($0.key) }
            try setAttributes(selected, destination.path)
        } catch { warnings.append(warning(for: destination, error: error)) }
        do {
            let sourceValues = try source.resourceValues(forKeys: [.tagNamesKey, .labelNumberKey])
            if sourceValues.labelNumber != nil {
                var values = URLResourceValues(); values.labelNumber = sourceValues.labelNumber
                var destinationURL = destination; try destinationURL.setResourceValues(values)
            }
        } catch { warnings.append(warning(for: destination, error: error)) }
        #if os(macOS)
        warnings.append(contentsOf: copyExtendedAttributes(from: source, to: destination))
        warnings.append(contentsOf: copyACL(from: source, to: destination))
        #endif
        return warnings
    }

    package func warning(for url: URL, error: Error) -> FileOperationCleanupWarning {
        FileOperationCleanupWarning(url: url, message: "PulseFiles copied item contents but could not preserve all metadata at %@: %@".localized(with: url.path, error.localizedDescription))
    }

    #if os(macOS)
    private func copyExtendedAttributes(from source: URL, to destination: URL) -> [FileOperationCleanupWarning] {
        let options = Int32(XATTR_NOFOLLOW)
        let size = listxattr(source.path, nil, 0, options)
        guard size >= 0 else { return errnoWarnings(for: source) }
        guard size > 0 else { return [] }
        var names = [CChar](repeating: 0, count: size)
        guard listxattr(source.path, &names, names.count, options) >= 0 else { return errnoWarnings(for: source) }
        var warnings: [FileOperationCleanupWarning] = []; var offset = 0
        while offset < names.count {
            let name = names.withUnsafeBufferPointer { $0.baseAddress.flatMap { String(validatingCString: $0.advanced(by: offset)) } }
            guard let name else { break }; offset += name.utf8.count + 1
            let valueSize = getxattr(source.path, name, nil, 0, 0, options)
            guard valueSize >= 0 else { warnings += errnoWarnings(for: source); continue }
            var value = [UInt8](repeating: 0, count: valueSize)
            guard getxattr(source.path, name, &value, value.count, 0, options) >= 0,
                  setxattr(destination.path, name, value, value.count, 0, options) == 0 else { warnings += errnoWarnings(for: destination); continue }
        }
        return warnings
    }

    private func copyACL(from source: URL, to destination: URL) -> [FileOperationCleanupWarning] {
        copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_ACL)) == 0 ? [] : errnoWarnings(for: destination)
    }

    private func errnoWarnings(for url: URL) -> [FileOperationCleanupWarning] {
        guard errno != ENOTSUP && errno != EOPNOTSUPP else { return [] }
        return [warning(for: url, error: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))]
    }
    #endif
}
