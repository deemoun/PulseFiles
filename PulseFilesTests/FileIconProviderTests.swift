import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class FileIconProviderTests: XCTestCase {
    func testReusesGenericIconsForEquivalentMetadata() {
        var resolutionCount = 0
        let provider = FileIconProvider(countLimit: 16) { _ in
            resolutionCount += 1
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let textFile = FileIconKey(fileType: .file, fileExtension: "txt", contentTypeIdentifier: "public.plain-text")

        let first = provider.image(for: textFile)
        let second = provider.image(for: textFile)
        let third = provider.image(for: FileIconKey(fileType: .file, fileExtension: "TXT", contentTypeIdentifier: "PUBLIC.PLAIN-TEXT"))

        XCTAssertTrue(first === second)
        XCTAssertTrue(second === third)
        XCTAssertEqual(resolutionCount, 1, "A directory with many matching files should resolve its generic icon once.")
    }

    func testKeepsFolderPackageSymbolicLinkAndFileIconMetadataDistinct() {
        var resolvedKeys: [FileIconKey] = []
        let provider = FileIconProvider(countLimit: 16) { key in
            resolvedKeys.append(key)
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let keys = [
            FileIconKey(fileType: .folder, fileExtension: ""),
            FileIconKey(fileType: .package, fileExtension: "app", contentTypeIdentifier: "com.apple.application-bundle"),
            FileIconKey(fileType: .symbolicLink, fileExtension: ""),
            FileIconKey(fileType: .file, fileExtension: "pdf", contentTypeIdentifier: "com.adobe.pdf")
        ]

        keys.forEach { _ = provider.image(for: $0) }

        XCTAssertEqual(resolvedKeys, keys)
        XCTAssertEqual(Set(resolvedKeys).count, 4)
    }

    func testInvalidationResolvesOnlyTheChangedIconMetadataAgain() {
        var resolutionCount = 0
        let provider = FileIconProvider(countLimit: 16) { _ in
            resolutionCount += 1
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let key = FileIconKey(fileType: .file, fileExtension: "zip")

        _ = provider.image(for: key)
        provider.invalidate(key)
        _ = provider.image(for: key)

        XCTAssertEqual(resolutionCount, 2)
    }
}
