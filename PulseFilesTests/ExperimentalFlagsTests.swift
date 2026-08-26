// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import PulseFiles

final class ExperimentalFlagsTests: XCTestCase {
    private var fixture: IsolatedDefaultsFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try IsolatedDefaultsFixture(prefix: "ExperimentalFlagsTests", testCase: self)
    }

    override func tearDownWithError() throws {
        fixture.cleanup()
        fixture = nil
        try super.tearDownWithError()
    }

    func testSandboxRestrictionDefaultsToDisabled() {
        XCTAssertFalse(ExperimentalFlags.isSandboxRestrictionEnabled(defaults: fixture.defaults, arguments: []))
    }

    func testDisableArgumentKeepsSandboxRestrictionDisabled() {
        fixture.defaults.set(true, forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey)

        XCTAssertFalse(
            ExperimentalFlags.isSandboxRestrictionEnabled(
                defaults: fixture.defaults,
                arguments: ["PulseFiles", "--pulsefiles-disable-experimental-sandbox"]
            )
        )
    }

    func testDebugBuildHonorsSandboxEnableFlagAndDefaultsKey() {
        #if DEBUG
        XCTAssertTrue(
            ExperimentalFlags.isSandboxRestrictionEnabled(
                defaults: fixture.defaults,
                arguments: ["PulseFiles", "--pulsefiles-enable-experimental-sandbox"]
            )
        )

        fixture.defaults.set(true, forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey)
        XCTAssertTrue(ExperimentalFlags.isSandboxRestrictionEnabled(defaults: fixture.defaults, arguments: []))

        fixture.defaults.set(false, forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey)
        XCTAssertFalse(ExperimentalFlags.isSandboxRestrictionEnabled(defaults: fixture.defaults, arguments: []))
        #else
        fixture.defaults.set(true, forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey)
        XCTAssertFalse(
            ExperimentalFlags.isSandboxRestrictionEnabled(
                defaults: fixture.defaults,
                arguments: ["PulseFiles", "--pulsefiles-enable-experimental-sandbox"]
            )
        )
        #endif
    }

    func testProductionBuildKeepsSandboxRestrictionDisabledEvenWithOptInInputs() {
        fixture.defaults.set(true, forKey: ExperimentalFlags.restrictFileAccessUserDefaultsKey)

        #if DEBUG
        XCTAssertTrue(
            ExperimentalFlags.isSandboxRestrictionEnabled(
                defaults: fixture.defaults,
                arguments: ["PulseFiles", "--pulsefiles-enable-experimental-sandbox"]
            )
        )
        #else
        XCTAssertFalse(
            ExperimentalFlags.isSandboxRestrictionEnabled(
                defaults: fixture.defaults,
                arguments: ["PulseFiles", "--pulsefiles-enable-experimental-sandbox"]
            )
        )
        #endif
    }
}
