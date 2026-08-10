import Foundation
import XCTest
@testable import PulseFiles

@MainActor
final class PaneFixture {
    let sandbox: SandboxFixture
    let root: URL
    let fileSystem: FileSystemService
    let accessPolicy: SandboxFileAccessPolicy
    let viewModel: FilePaneViewModel

    init(
        showsHiddenFiles: Bool = false,
        sort: FileSortDescriptor = FileSortDescriptor(),
        testCase: XCTestCase? = nil
    ) throws {
        sandbox = try SandboxFixture(testCase: testCase)
        root = sandbox.allowedDirectory
        accessPolicy = sandbox.policy
        fileSystem = FileSystemService(accessPolicy: accessPolicy, scheduler: FileSystemOperationScheduler())
        viewModel = FilePaneViewModel(
            initialDirectory: root,
            showsHiddenFiles: showsHiddenFiles,
            sort: sort,
            fileSystem: fileSystem,
            accessPolicy: accessPolicy
        )
    }

    @discardableResult
    func makeFoldersFirstLayout() throws -> [URL] {
        [
            try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Zebra Folder"),
            try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Alpha Folder"),
            try sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/beta.txt", contents: "beta"),
            try sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/alpha.txt", contents: "alpha")
        ]
    }

    @discardableResult
    func makeHiddenFilesLayout() throws -> [URL] {
        [
            try sandbox.temporaryDirectory.hiddenFile("AllowedSandbox/Allowed/env", contents: "secret"),
            try sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/Visible.txt", contents: "visible")
        ]
    }

    @discardableResult
    func makeDuplicateNamesLayout() throws -> [URL] {
        [
            try sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/Report.txt", contents: "root"),
            try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Nested"),
            try sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/Nested/Report.txt", contents: "nested")
        ]
    }

    @discardableResult
    func makeSymlinkLayout() throws -> [URL] {
        let target = try sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/Target.txt", contents: "target")
        let link = root.appendingPathComponent("Target Link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return [target, link]
    }

    @discardableResult
    func makeSearchLayout() throws -> [URL] {
        [
            try sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/Quarterly Report.txt", contents: "report"),
            try sandbox.temporaryDirectory.file("AllowedSandbox/Allowed/Notes.md", contents: "notes"),
            try sandbox.temporaryDirectory.folder("AllowedSandbox/Allowed/Reports Archive")
        ]
    }
}
