// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import PulseFiles

@MainActor
final class AboutWindowUITests: XCTestCase {
    func testAboutWindowExposesLicenseWarrantyAndKeyboardAccessibleLinks() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let window = delegate.makeAboutWindow()
        window.contentView?.layoutSubtreeIfNeeded()

        let licenseNotice = try XCTUnwrap(view("about.licenseNotice", in: window.contentView) as? NSTextField)
        let warrantyNotice = try XCTUnwrap(view("about.warrantyNotice", in: window.contentView) as? NSTextField)
        let licenseButton = try XCTUnwrap(view("about.viewLicense", in: window.contentView) as? NSButton)
        let sourceButton = try XCTUnwrap(view("about.viewSource", in: window.contentView) as? NSButton)

        XCTAssertTrue(licenseNotice.stringValue.contains("GPL-3.0-or-later"))
        XCTAssertTrue(warrantyNotice.stringValue.localizedCaseInsensitiveContains("without warranty"))
        XCTAssertEqual(licenseButton.keyEquivalent, "l")
        XCTAssertEqual(licenseButton.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(sourceButton.keyEquivalent, "s")
        XCTAssertEqual(sourceButton.keyEquivalentModifierMask, [.command])
        XCTAssertFalse(licenseButton.accessibilityLabel()?.isEmpty ?? true)
        XCTAssertFalse(sourceButton.accessibilityLabel()?.isEmpty ?? true)
        XCTAssertEqual(AppDelegate.sourceRepositoryURL.absoluteString, "https://github.com/deemoun/PulseFiles")
    }

    private func view(_ identifier: String, in root: NSView?) -> NSView? {
        guard let root else { return nil }
        if root.accessibilityIdentifier() == identifier { return root }
        return root.subviews.lazy.compactMap { view(identifier, in: $0) }.first
    }
}
