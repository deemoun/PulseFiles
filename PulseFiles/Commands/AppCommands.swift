// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import PulseFilesUtilities
import PulseFilesModels
import PulseFilesServices
import Foundation

package enum CommandBarAction: String, CaseIterable {
    case rename = "Rename"
    case batchRename = "Batch Rename"
    case createArchive = "Create Archive"
    case extractArchive = "Extract Archive"
    case view = "View"
    case copy = "Copy"
    case move = "Move"
    case newFolder = "New Folder"
    case newFile = "New File"
    case delete = "Delete"
    case cancelOperation = "Cancel Operation"
    case newTab = "New Tab"
    case closeTab = "Close Tab"
    case nextTab = "Next Tab"
    case previousTab = "Previous Tab"

    package var title: String {
        switch self {
        case .rename: return "Rename".localized
        case .batchRename: return "Batch Rename".localized
        case .createArchive: return "Create Archive".localized
        case .extractArchive: return "Extract Archive".localized
        case .view: return "Viewer".localized
        case .copy: return "Copy".localized
        case .move: return "Move".localized
        case .newFolder: return "New Folder".localized
        case .newFile: return "New File".localized
        case .delete: return "Delete".localized
        case .cancelOperation: return "Cancel Operation".localized
        case .newTab: return "New Tab".localized
        case .closeTab: return "Close Tab".localized
        case .nextTab: return "Next Tab".localized
        case .previousTab: return "Previous Tab".localized
        }
    }
}
