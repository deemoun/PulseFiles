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

    func testSandboxDisabledModeIsRepresentedInWarningState() {
        let warning = service.warningState(settings: settings, accessPolicy: sandboxFixture.unrestrictedPolicy)

        XCTAssertFalse(warning.areSandboxRestrictionsEnabled)
        XCTAssertTrue(warning.informativeText.localizedCaseInsensitiveContains("outside PulseFiles"))
        XCTAssertTrue(warning.informativeText.localizedCaseInsensitiveContains("sandbox restrictions are disabled"))
    }

    @MainActor
    func testStoppingRunningTerminalCommandClearsHandlerTerminatesAndReportsTermination() {
        let process = FakeTerminalProcess()
        let controller = TerminalViewController(processFactory: { process })
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("sleep 10")

        XCTAssertTrue(process.didRun)
        XCTAssertNotNil(process.outputPipe?.fileHandleForReading.readabilityHandler)

        controller.stopRunningCommand()

        XCTAssertNil(process.outputPipe?.fileHandleForReading.readabilityHandler)
        XCTAssertTrue(process.didTerminate)
        XCTAssertTrue(controller.terminalTextForTesting.contains("[terminated]"))
    }

    @MainActor
    func testStoppingFinishedTerminalCommandClearsHandlerWithoutTerminationMessage() {
        let process = FakeTerminalProcess()
        process.isRunning = false
        let controller = TerminalViewController(processFactory: { process })
        controller.loadView()
        controller.viewDidLoad()

        controller.runCommandForTesting("echo done")
        controller.stopRunningCommand()

        XCTAssertNil(process.outputPipe?.fileHandleForReading.readabilityHandler)
        XCTAssertFalse(process.didTerminate)
        XCTAssertFalse(controller.terminalTextForTesting.contains("[terminated]"))
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
    var terminationHandler: ((TerminalProcess) -> Void)?

    private(set) var didRun = false
    private(set) var didTerminate = false
    private(set) var outputPipe: Pipe?
    private(set) var currentDirectoryURL: URL?

    func configure(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL,
        outputPipe: Pipe
    ) {
        self.currentDirectoryURL = currentDirectoryURL
        self.outputPipe = outputPipe
    }

    func run() throws {
        didRun = true
    }

    func terminate() {
        didTerminate = true
        isRunning = false
    }
}
