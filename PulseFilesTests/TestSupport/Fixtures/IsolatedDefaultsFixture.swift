// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

final class IsolatedDefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    init(prefix: String = "PulseFilesTests", testCase: XCTestCase? = nil) throws {
        suiteName = "\(prefix).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.defaults = defaults
        defaults.removePersistentDomain(forName: suiteName)
        testCase?.addTeardownBlock { [suiteName] in
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
