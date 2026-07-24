import XCTest
@testable import PulseFiles

final class TerminalBehaviorTests: XCTestCase {
    private var defaultsFixture: IsolatedDefaultsFixture!
    private var sandboxFixture: SandboxFixture!
    private var settings: SettingsService!
    private var service: TerminalService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsFixture = try IsolatedDefaultsFixture(prefix: "TerminalBehaviorTests", testCase: self)
        sandboxFixture = try SandboxFixture(testCase: self)
        settings = SettingsService(defaults: defaultsFixture.defaults)
        service = TerminalService()
    }

    override func tearDownWithError() throws {
        defaultsFixture.cleanup()
        settings = nil
        service = nil
        sandboxFixture = nil
        defaultsFixture = nil
        try super.tearDownWithError()
    }

    func testTerminalRemainsDisabledByDefault() {
        let state = service.defaultVisibilityState(settings: settings)

        XCTAssertFalse(state.isExperimentEnabled)
        XCTAssertFalse(state.isVisibleByDefault)
        XCTAssertFalse(settings.isTerminalVisible)
    }

    func testExperimentalTerminalMustBeEnabledBeforeDefaultVisibilityCanBeEnabled() {
        settings.defaultTerminalVisible = true

        XCTAssertFalse(service.defaultVisibilityState(settings: settings).isVisibleByDefault)

        settings.experimentalTerminalEnabled = true
        settings.defaultTerminalVisible = true

        let reloadedSettings = SettingsService(defaults: defaultsFixture.defaults)
        let state = service.defaultVisibilityState(settings: reloadedSettings)
        XCTAssertTrue(state.isExperimentEnabled)
        XCTAssertTrue(state.isVisibleByDefault)
    }

    func testFirstUseWarningAcknowledgementIsPersisted() {
        XCTAssertFalse(service.warningState(settings: settings, accessPolicy: sandboxFixture.policy).isAcknowledged)

        service.acknowledgeFirstUseWarning(settings: settings)

        let reloadedSettings = SettingsService(defaults: defaultsFixture.defaults)
        XCTAssertTrue(service.warningState(settings: reloadedSettings, accessPolicy: sandboxFixture.policy).isAcknowledged)
    }

    func testFirstUseWarningAcknowledgementRequiresAcknowledgementResponse() {
        XCTAssertTrue(service.shouldAcknowledgeFirstUseWarning(response: 1000, acknowledgementResponse: 1000))
        XCTAssertFalse(service.shouldAcknowledgeFirstUseWarning(response: 1001, acknowledgementResponse: 1000))
    }

    func testWorkingDirectoryFollowsActivePaneWhenURLIsAllowed() {
        let workingDirectory = service.resolvedWorkingDirectory(
            activePaneURL: sandboxFixture.allowedDirectory,
            accessPolicy: sandboxFixture.policy
        )

        XCTAssertEqual(workingDirectory, sandboxFixture.allowedDirectory)
    }

    func testWorkingDirectoryFallsBackWhenActivePaneURLIsUnavailableOrDisallowed() {
        XCTAssertEqual(
            service.resolvedWorkingDirectory(activePaneURL: nil, accessPolicy: sandboxFixture.policy),
            sandboxFixture.root
        )

        XCTAssertEqual(
            service.resolvedWorkingDirectory(activePaneURL: sandboxFixture.externalDirectory, accessPolicy: sandboxFixture.policy),
            sandboxFixture.root
        )
    }

    func testWorkingDirectoryAllowsExternalPaneURLWhenSandboxRestrictionsAreDisabled() {
        let workingDirectory = service.resolvedWorkingDirectory(
            activePaneURL: sandboxFixture.externalDirectory,
            accessPolicy: sandboxFixture.unrestrictedPolicy
        )

        XCTAssertEqual(workingDirectory, sandboxFixture.externalDirectory)
    }

    func testFirstUseWarningDescribesAuthorizedLocationRisk() {
        let warning = service.warningState(settings: settings, accessPolicy: sandboxFixture.unrestrictedPolicy)

        XCTAssertFalse(warning.areSandboxRestrictionsEnabled)
        XCTAssertEqual(warning.messageText, "Beta Terminal warning".localized)
        XCTAssertTrue(warning.informativeText.localizedCaseInsensitiveContains("modify or delete files"))
        XCTAssertTrue(warning.informativeText.localizedCaseInsensitiveContains("any locations macOS has authorized for PulseFiles"))
    }

    @MainActor
    func testStopTerminatesPersistentSessionAndReportsTermination() {
        let process = FakeTerminalProcess()
        let controller = TerminalViewController(processFactory: { process })
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("cd /tmp")
        controller.runCommandForTesting("pwd")

        XCTAssertTrue(process.didRun)
        XCTAssertEqual(process.writes, ["cd /tmp\n", "pwd\n"])

        controller.stopRunningCommand()

        XCTAssertTrue(process.didTerminate)
        XCTAssertTrue(controller.terminalTextForTesting.contains("[terminated]"))
    }

    @MainActor
    func testStoppingFinishedTerminalSessionDoesNotReportTermination() {
        let process = FakeTerminalProcess()
        process.isRunning = false
        let controller = TerminalViewController(processFactory: { process })
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("echo done")
        controller.stopRunningCommand()

        XCTAssertFalse(process.didTerminate)
        XCTAssertFalse(controller.terminalTextForTesting.contains("[terminated]"))
    }

    @MainActor
    func testResetSessionStopsCommandAndClearsPriorTerminalOutput() {
        let process = FakeTerminalProcess()
        let controller = TerminalViewController(processFactory: { process })
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("sleep 10")
        controller.receiveOutputForTesting("previous command output\n")
        controller.resetSession()

        XCTAssertTrue(process.didTerminate)
        XCTAssertFalse(controller.terminalTextForTesting.contains("sleep 10"))
        XCTAssertFalse(controller.terminalTextForTesting.contains("previous command output"))
        XCTAssertFalse(controller.terminalTextForTesting.contains("[terminated]"))
        XCTAssertTrue(controller.terminalTextForTesting.contains("[terminal reset]"))
    }

    @MainActor
    func testTerminalCommandDoesNotLaunchBeforeFirstUseWarningAcknowledgement() {
        let process = FakeTerminalProcess()
        let controller = TerminalViewController(processFactory: { process }, accessPolicy: sandboxFixture.policy)
        controller.isShellInteractionAllowedProvider = { false }
        controller.suggestedWorkingDirectory = sandboxFixture.allowedDirectory
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("pwd")

        XCTAssertFalse(process.didRun)
        XCTAssertNil(process.currentDirectoryURL)
        XCTAssertTrue(controller.terminalTextForTesting.contains("Acknowledge the Beta Terminal warning"))
    }

    @MainActor
    func testTerminalCommandDoesNotLaunchWhenWorkingDirectoryIsDenied() {
        let process = FakeTerminalProcess()
        let controller = TerminalViewController(processFactory: { process }, accessPolicy: sandboxFixture.policy)
        controller.suggestedWorkingDirectory = sandboxFixture.externalDirectory
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("pwd")

        XCTAssertFalse(process.didRun)
        XCTAssertNil(process.currentDirectoryURL)
        XCTAssertTrue(controller.terminalTextForTesting.contains("working directory is not authorized"))
    }

    @MainActor
    func testTerminalCommandUsesGrantedWorkingDirectoryOutsideSandboxRoot() throws {
        let grantDefaults = try IsolatedDefaultsFixture(prefix: "TerminalBehaviorGrantTests", testCase: self)
        defer { grantDefaults.cleanup() }
        let grantService = FolderAccessGrantService(defaults: grantDefaults.defaults, resolver: TerminalBehaviorFakeBookmarkResolver())
        try grantService.grantAccess(to: sandboxFixture.externalDirectory)
        let policy = SandboxFileAccessPolicy(isEnabled: true, rootURL: sandboxFixture.root, grantService: grantService)
        let process = FakeTerminalProcess()
        let controller = TerminalViewController(processFactory: { process }, accessPolicy: policy)
        controller.suggestedWorkingDirectory = sandboxFixture.externalDirectory
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("pwd")

        XCTAssertTrue(process.didRun)
        XCTAssertEqual(process.currentDirectoryURL, sandboxFixture.externalDirectory)
    }

    @MainActor
    func testHighVolumeOutputIsBoundedAndReturnsToPromptAfterCompletion() {
        let process = FakeTerminalProcess()
        let controller = TerminalViewController(processFactory: { process }, accessPolicy: sandboxFixture.policy)
        controller.suggestedWorkingDirectory = sandboxFixture.allowedDirectory
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("noisy-command")
        controller.receiveOutputForTesting(String(repeating: "output line\n", count: 30_000))
        controller.flushOutputForTesting()
        process.complete()

        let completion = expectation(description: "terminal completion")
        DispatchQueue.main.async { completion.fulfill() }
        wait(for: [completion], timeout: 1)

        let text = controller.terminalTextForTesting
        XCTAssertLessThanOrEqual(text.utf8.count, TerminalViewController.maximumRetainedOutputBytes)
        XCTAssertLessThanOrEqual(text.count, TerminalViewController.maximumRetainedOutputCharacters)
        XCTAssertLessThanOrEqual(text.filter { $0 == "\n" }.count, TerminalViewController.maximumRetainedOutputLines)
        XCTAssertTrue(text.contains("[Earlier terminal output truncated]"))
        XCTAssertTrue(text.contains("[shell exited]"))
    }

    @MainActor
    func testStoppingNoisyCommandClearsHandlersAndAccessScope() {
        let process = FakeTerminalProcess()
        let controller = TerminalViewController(processFactory: { process }, accessPolicy: sandboxFixture.policy)
        controller.suggestedWorkingDirectory = sandboxFixture.allowedDirectory
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("noisy-command")
        controller.receiveOutputForTesting(String(repeating: "output\n", count: 10_000))
        XCTAssertTrue(controller.hasRunningAccessScopeForTesting)

        controller.stopRunningCommand()

        XCTAssertNil(process.terminationHandler)
        XCTAssertFalse(controller.hasRunningAccessScopeForTesting)
    }
}

private struct TerminalBehaviorFakeBookmarkResolver: FolderAccessBookmarkResolving {
    func makeBookmarkData(for url: URL) throws -> Data {
        Data(url.standardizedFileURL.path.utf8)
    }

    func resolveBookmarkData(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (URL(fileURLWithPath: path, isDirectory: true), false)
    }
}

private final class FakeTerminalProcess: TerminalProcess {
    var isRunning = true
    var terminationStatus: Int32 = 0
    var terminationReason: Process.TerminationReason = .exit
    var outputHandler: ((Data) -> Void)?
    var terminationHandler: ((TerminalProcess) -> Void)?

    private(set) var didRun = false
    private(set) var didTerminate = false
    private(set) var currentDirectoryURL: URL?
    private(set) var writes: [String] = []

    func configure(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL,
    ) {
        self.currentDirectoryURL = currentDirectoryURL
    }

    func run() throws {
        didRun = true
    }

    func terminate() {
        didTerminate = true
        isRunning = false
    }

    func write(_ data: Data) {
        writes.append(String(decoding: data, as: UTF8.self))
    }

    func resize(columns: Int, rows: Int) {}

    func complete(status: Int32 = 0) {
        terminationStatus = status
        isRunning = false
        terminationHandler?(self)
    }
}
