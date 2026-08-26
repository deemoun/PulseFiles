// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import PulseFiles

final class LiquidGlassStyleTests: XCTestCase {
    func testInjectedSettingsControlPanelStyleRegardlessOfStandardDefaults() throws {
        let fixture = try IsolatedDefaultsFixture(prefix: "LiquidGlassStyleTests", testCase: self)
        let unrelatedFixture = try IsolatedDefaultsFixture(prefix: "UnrelatedLiquidGlassDefaults", testCase: self)
        let settings = SettingsService(defaults: fixture.defaults)
        let unrelatedSettings = SettingsService(defaults: unrelatedFixture.defaults)
        unrelatedSettings.liquidGlassEnabled = true

        settings.liquidGlassEnabled = false
        let standardStyle = LiquidGlassStyle(liquidGlassEnabled: settings.liquidGlassEnabled)
        let standardPanel = NSView()
        standardStyle.applyPanelChrome(to: standardPanel)
        XCTAssertFalse(standardStyle.isEnabled)
        XCTAssertEqual(standardPanel.layer?.cornerRadius, LiquidGlassStyle.compactCornerRadius)

        settings.liquidGlassEnabled = true
        let glassStyle = LiquidGlassStyle(liquidGlassEnabled: settings.liquidGlassEnabled)
        let glassPanel = NSView()
        glassStyle.applyPanelChrome(to: glassPanel)
        XCTAssertTrue(glassStyle.isEnabled)
        XCTAssertEqual(glassPanel.layer?.cornerRadius, LiquidGlassStyle.cornerRadius)
    }

    func testInjectedSettingsControlButtonChrome() throws {
        let fixture = try IsolatedDefaultsFixture(prefix: "LiquidGlassButtonStyleTests", testCase: self)
        let settings = SettingsService(defaults: fixture.defaults)
        let button = NSButton()

        settings.liquidGlassEnabled = false
        LiquidGlassStyle(liquidGlassEnabled: settings.liquidGlassEnabled).applyButtonChrome(to: button)
        XCTAssertTrue(button.isBordered)
        XCTAssertEqual(button.layer?.borderWidth, 0)

        settings.liquidGlassEnabled = true
        LiquidGlassStyle(liquidGlassEnabled: settings.liquidGlassEnabled).applyButtonChrome(to: button)
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.layer?.borderWidth, 1)
    }
}
