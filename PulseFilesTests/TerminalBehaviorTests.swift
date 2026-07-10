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
}

private final class FakeTerminalProcess: TerminalProcess {
    var isRunning = true
    var terminationStatus: Int32 = 0
    var terminationReason: Process.TerminationReason = .exit
    var terminationHandler: ((TerminalProcess) -> Void)?

    private(set) var didRun = false
    private(set) var didTerminate = false
    private(set) var outputPipe: Pipe?

    func configure(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL,
        outputPipe: Pipe
    ) {
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
