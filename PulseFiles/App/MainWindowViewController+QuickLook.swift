// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Quartz

extension MainWindowViewController {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        previewPresentationAdapter.connect(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        previewPresentationAdapter.disconnect(panel)
    }
}
