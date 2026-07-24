#if canImport(AppKit)
import AppKit
#endif
import Foundation
#if os(macOS)
import Darwin
#endif

enum SandboxAccessError: LocalizedError, Equatable {
    case outsideExperimentalSandbox(URL)
    case unauthorized(URL)

    var errorDescription: String? {
        switch self {
        case .outsideExperimentalSandbox:
            return "Experimental sandbox mode is enabled.".localized
        case .unauthorized:
            return "Folder access is not authorized.".localized
        }
    }

    var failureReason: String? {
        switch self {
        case .outsideExperimentalSandbox(let url):
            return "%@ is outside the PulseFiles experimental sandbox.".localized(with: url.path)
        case .unauthorized(let url):
            return "%@ is not currently readable by PulseFiles. Choose a folder you can access or grant access first.".localized(with: url.path)
        }
    }
}

struct SandboxFileAccessPolicy {
    struct AccessProbe {
        let fileExists: (String) -> Bool
        let isReadableFile: (String) -> Bool
        let isWritableFile: (String) -> Bool

        static let fileManagerDefault = AccessProbe(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            isReadableFile: { FileManager.default.isReadableFile(atPath: $0) },
            isWritableFile: { FileManager.default.isWritableFile(atPath: $0) }
        )
    }

    private let isEnabledOverride: Bool?
    private let grantService: FolderAccessGrantService
    private let accessProbe: AccessProbe
    let rootURL: URL

    static let current = SandboxFileAccessPolicy(
        rootURL: ExperimentalFlags.appSandboxRoot
    )

    init(
        isEnabled: Bool? = nil,
        rootURL: URL,
        grantService: FolderAccessGrantService = .shared,
        accessProbe: AccessProbe = .fileManagerDefault
    ) {
        self.isEnabledOverride = isEnabled
        self.rootURL = rootURL
        self.grantService = grantService
        self.accessProbe = accessProbe
    }

    var isEnabled: Bool {
        isEnabledOverride ?? ExperimentalFlags.restrictFileAccessToAppSandboxRoot
    }

    func canAccess(_ url: URL, logDecision shouldLogDecision: Bool = true) -> Bool {
        let allowed: Bool
        let reason: String
        if isEnabled {
            if isInsideExperimentalSandbox(url) {
                allowed = true
                reason = "inside sandbox root"
            } else if hasUsableGrant(to: url) {
                allowed = true
                reason = "explicit folder access grant"
            } else {
                allowed = false
                reason = "outside sandbox root and not explicitly granted"
            }
        } else {
            allowed = hasProcessAccess(to: url) || hasUsableGrant(to: url)
            reason = allowed ? "directly readable, security-scoped, or granted" : "not readable or not authorized"
        }
        if shouldLogDecision {
            logDecision(allowed ? .debug : .warning, allowed: allowed, url: url, reason: reason)
        }
        return allowed
    }

    func validateAccess(to url: URL) throws {
        guard canAccess(url) else {
            let reason = isEnabled ? "outside sandbox root" : "not readable or not authorized"
            DiagnosticLogger.log(.warning, category: "Sandbox", "Denied access validation: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(reason)")
            throw isEnabled ? SandboxAccessError.outsideExperimentalSandbox(url) : SandboxAccessError.unauthorized(url)
        }
    }

    /// Determines whether a protected-folder consent read may be attempted.
    /// Normal mode leaves the actual decision to macOS/TCC; experimental sandbox
    /// mode must still reject paths outside its root unless separately granted.
    func canAttemptProtectedFolderAccess(_ url: URL) -> Bool {
        guard isEnabled else { return true }
        return canAccess(url)
    }

    func validateDestinationAccess(to destination: URL) throws {
        let parentDirectory = destination.deletingLastPathComponent()
        let allowed: Bool
        let reason: String

        if isEnabled {
            if isInsideExperimentalSandbox(parentDirectory) {
                allowed = true
                reason = "parent inside sandbox root"
            } else if hasUsableGrant(to: parentDirectory, requireWritable: true) {
                allowed = true
                reason = "parent inside explicit folder access grant"
            } else {
                allowed = false
                reason = "parent outside sandbox root and not explicitly granted"
            }
        } else {
            allowed = hasProcessAccess(to: parentDirectory, requireWritable: true) || hasUsableGrant(to: parentDirectory, requireWritable: true)
            reason = allowed ? "parent directly readable and writable, security-scoped, or granted" : "parent not writable or not authorized"
        }

        logDecision(allowed ? .debug : .warning, allowed: allowed, url: destination, reason: reason)
        guard allowed else {
            DiagnosticLogger.log(.warning, category: "Sandbox", "Denied destination access validation: destination=\(DiagnosticLogger.sanitizedPath(destination)); parent=\(DiagnosticLogger.sanitizedPath(parentDirectory)); reason=\(reason)")
            throw isEnabled ? SandboxAccessError.outsideExperimentalSandbox(destination) : SandboxAccessError.unauthorized(destination)
        }
    }

    func validatedDirectory(_ url: URL, fallback: URL? = nil) -> URL {
        if canAccess(url) {
            return url
        }

        if let fallback, fallback != url, canAccess(fallback) {
            DiagnosticLogger.log(.warning, category: "Sandbox", "Rejected denied directory and preserved fallback: requested=\(DiagnosticLogger.sanitizedPath(url)); fallback=\(DiagnosticLogger.sanitizedPath(fallback))")
            return fallback
        }

        if isEnabled, canAccess(rootURL) {
            DiagnosticLogger.log(.warning, category: "Sandbox", "Redirected denied directory to sandbox root: requested=\(DiagnosticLogger.sanitizedPath(url))")
            return rootURL
        }

        DiagnosticLogger.log(.warning, category: "Sandbox", "Rejected denied directory with no accessible fallback: requested=\(DiagnosticLogger.sanitizedPath(url))")
        return fallback ?? url
    }

    #if canImport(AppKit)
    @MainActor
    func requestAccess(to directory: URL, window: NSWindow?, completion: @escaping (Bool) -> Void) {
        if canAccess(directory) {
            completion(true)
            return
        }

        let panel = NSOpenPanel()
        panel.directoryURL = directory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access".localized
        panel.message = "Choose a folder to grant PulseFiles access.".localized

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let selectedURL = panel.url else {
                completion(false)
                return
            }
            completion(grantSelectedFolder(selectedURL, for: directory))
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
    #endif

    /// Completes a folder-picker decision. Kept separate from AppKit so the
    /// containment and post-grant validation are testable.
    @discardableResult
    func grantSelectedFolder(_ selectedFolder: URL, for requestedDirectory: URL) -> Bool {
        do {
            let grant = try grantService.grantAccess(to: selectedFolder)
            guard contains(requestedDirectory, within: grant.url), canAccess(requestedDirectory) else {
                return false
            }
            return true
        } catch {
            return false
        }
    }


    /// Validates a read path and keeps any matching security-scoped bookmark
    /// active for the complete filesystem operation.  Use this rather than
    /// separating `validateAccess` from a later read: a bookmark scope opened
    /// merely for validation is intentionally closed before validation returns.
    func withValidatedAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
        try withValidatedAccess(to: [url], body)
    }

    func withValidatedAccess<T>(to urls: [URL], _ body: () throws -> T) throws -> T {
        for url in urls {
            try validateAccess(to: url)
        }
        return try grantService.withSecurityScopedAccess(to: urls, body)
    }

    func withValidatedAccess<T>(to url: URL, _ body: () async throws -> T) async throws -> T {
        try await withValidatedAccess(to: [url], body)
    }

    func withValidatedAccess<T>(to urls: [URL], _ body: () async throws -> T) async throws -> T {
        for url in urls {
            try validateAccess(to: url)
        }
        return try await grantService.withSecurityScopedAccess(to: urls, body)
    }

    /// Opens scopes without validation for mutation code that has already
    /// completed its preflight. Read paths should use `withValidatedAccess`.
    func withAccess<T>(to urls: [URL], _ body: () throws -> T) rethrows -> T {
        try grantService.withSecurityScopedAccess(to: urls, body)
    }

    func withAccess<T>(to urls: [URL], _ body: () async throws -> T) async rethrows -> T {
        try await grantService.withSecurityScopedAccess(to: urls, body)
    }

    func beginAccess(to urls: [URL]) -> FolderAccessScope {
        grantService.beginSecurityScopedAccess(to: urls)
    }

    func endAccess(_ scope: FolderAccessScope) {
        grantService.endSecurityScopedAccess(scope)
    }

    private func isInsideExperimentalSandbox(_ url: URL) -> Bool {
        let rootPath = normalizedPath(rootURL)
        let candidatePath = normalizedPath(url)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func hasProcessAccess(to url: URL, requireWritable: Bool = false) -> Bool {
        let didStartScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let path = normalizedPath(url)
        guard accessProbe.fileExists(path), accessProbe.isReadableFile(path) else { return false }
        if requireWritable {
            return accessProbe.isWritableFile(path)
        }
        return true
    }

    private func hasUsableGrant(to url: URL, requireWritable: Bool = false) -> Bool {
        grantService.grantStatus(
            containing: url,
            requireWritable: requireWritable,
            canRead: { accessProbe.fileExists($0) && accessProbe.isReadableFile($0) },
            canWrite: accessProbe.isWritableFile
        ) == .available
    }

    private func contains(_ candidate: URL, within container: URL) -> Bool {
        let containerPath = normalizedPath(container)
        let candidatePath = normalizedPath(candidate)
        return candidatePath == containerPath || candidatePath.hasPrefix(containerPath + "/")
    }

    private func logDecision(_ level: DiagnosticLogLevel, allowed: Bool, url: URL, reason: String) {
        DiagnosticLogger.log(level, category: "Sandbox", "\(allowed ? "Allowed" : "Denied") access decision: path=\(DiagnosticLogger.sanitizedPath(url)); reason=\(reason)")
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// A directory capability used by filesystem mutations.  The descriptor is
/// opened component-by-component without following links; callers must use
/// `*at` APIs with its descriptor rather than reconstructing an absolute path.
#if os(macOS)
struct OpenDirectoryCapability {
    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    let fileDescriptor: Int32
    let identity: Identity
    /// Retained only for diagnostics and test-copier compatibility. Mutation
    /// callers must use `fileDescriptor` with an `*at` syscall.
    let directoryURL: URL

    init(directory url: URL) throws {
        let components = url.standardizedFileURL.pathComponents
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            for component in components where component != "/" {
                guard component != ".", component != "..", !component.contains("/") else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                let next = component.withCString { Darwin.openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
                guard next >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                Darwin.close(descriptor)
                descriptor = next
            }
            var status = stat()
            guard Darwin.fstat(descriptor, &status) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard (status.st_mode & S_IFMT) == S_IFDIR else { throw POSIXError(.ENOTDIR) }
            fileDescriptor = descriptor
            identity = Identity(device: status.st_dev, inode: status.st_ino)
            directoryURL = url
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    func revalidate() throws {
        var status = stat()
        guard Darwin.fstat(fileDescriptor, &status) == 0,
              status.st_dev == identity.device, status.st_ino == identity.inode,
              (status.st_mode & S_IFMT) == S_IFDIR else {
            throw POSIXError(.ESTALE)
        }
    }

    func itemIdentity(named name: String) throws -> Identity {
        try Self.validateName(name)
        var status = stat()
        guard name.withCString({ Darwin.fstatat(fileDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW) }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        guard (status.st_mode & S_IFMT) != S_IFLNK else { throw POSIXError(.ELOOP) }
        return Identity(device: status.st_dev, inode: status.st_ino)
    }

    func requireItem(named name: String, identity expected: Identity? = nil) throws {
        try revalidate()
        let actual = try itemIdentity(named: name)
        guard expected == nil || actual == expected else { throw POSIXError(.ESTALE) }
    }

    static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { throw CocoaError(.fileReadInvalidFileName) }
    }

    func close() { Darwin.close(fileDescriptor) }

    func createDirectory(named name: String, mode: mode_t = 0o755) throws {
        try revalidate(); try Self.validateName(name)
        guard name.withCString({ Darwin.mkdirat(fileDescriptor, $0, mode) }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func createSymbolicLink(named name: String, destination: String) throws {
        try revalidate(); try Self.validateName(name)
        guard name.withCString({ namePointer in destination.withCString { Darwin.symlinkat($0, fileDescriptor, namePointer) } }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func openNewRegularFile(named name: String, mode: mode_t = 0o644) throws -> Int32 {
        try revalidate(); try Self.validateName(name)
        let descriptor = name.withCString { Darwin.openat(fileDescriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode) }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return descriptor
    }

    func renameItem(named name: String, to destination: OpenDirectoryCapability, named destinationName: String) throws {
        try requireItem(named: name)
        try destination.revalidate(); try Self.validateName(destinationName)
        guard name.withCString({ source in destinationName.withCString { Darwin.renameat(fileDescriptor, source, destination.fileDescriptor, $0) } }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func removeItem(named name: String) throws {
        // `fstatat(..., AT_SYMLINK_NOFOLLOW)` deliberately inspects the link
        // object. A staged copy may itself be a symlink, which must be
        // removable without resolving its target.
        try revalidate(); try Self.validateName(name)
        var status = stat()
        guard name.withCString({ Darwin.fstatat(fileDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW) }) == 0 else { throw POSIXError(.ENOENT) }
        let flags: Int32 = (status.st_mode & S_IFMT) == S_IFDIR ? AT_REMOVEDIR : 0
        guard name.withCString({ Darwin.unlinkat(fileDescriptor, $0, flags) }) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
#endif
