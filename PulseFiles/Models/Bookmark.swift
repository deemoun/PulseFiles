// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PulseFilesUtilities

package struct Bookmark: Codable, Identifiable, Equatable {
    package var id: UUID
    package var title: String
    package var url: URL

    package init(id: UUID = UUID(), title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}
