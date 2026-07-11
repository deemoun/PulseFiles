# PulseFiles Release Notes Draft

## Overview

PulseFiles is a native macOS file manager built with AppKit and Swift Package Manager. It focuses on a fast, keyboard-first workflow with two independently navigable file panes for comparing, browsing, and operating on files side by side.

## Supported Platform

- macOS 13 Ventura or newer.
- Built as a native AppKit application; no SwiftUI runtime or cross-platform UI layer is required for the core interface.

## Core File Manager Experience

- Dual-pane browser layout with independently navigable left and right panes.
- Folder-first listings with sortable columns for name, size, and modification date.
- Breadcrumb navigation for moving through path components.
- Multiple selection in file panes.
- Active-pane indication so commands, filtering, and operations apply predictably.
- Optional sidebar and command bar surfaces for navigation and command access.

## Keyboard-First Navigation

PulseFiles is designed for keyboard-driven browsing and file management, including:

- Return to open the selected directory or file.
- Backspace and Command-Up to navigate to a parent directory where allowed.
- Tab to switch the active pane.
- Command shortcuts for common actions such as copy, move, search, hidden-file visibility, and file operations.
- Command routing that avoids taking over standard text-editing shortcuts while search fields or dialogs are focused.

## Supported File Operations

PulseFiles supports common file-manager operations through its file-operation service layer:

- Copy selected files or folders to the opposite pane or chosen destination.
- Move selected files or folders.
- Rename files and folders.
- Move items to Trash.
- Permanently delete items when that preference/command path is enabled.
- Clipboard-style copy, cut, and paste flows.
- Open, reveal, Quick Look, and Open With style command routing where supported by the host system.

File operations are preflighted before mutation. The app is intended to reject unsafe or ambiguous requests such as empty selections, duplicate sources, invalid destinations, missing sources, and destination-inside-source copy/move requests. Conflict handling should use replace, skip, or cancel choices rather than silently overwriting files.

## Search, Filtering, and Hidden Files

- Search/filter applies to the active pane.
- Search mode hides the synthetic parent row (`..`) so filtered results do not expose unintended navigation shortcuts.
- Hidden files can be shown or hidden, including a persisted default preference for hidden-file visibility.
- File listings preserve folder-first sorting behavior while supporting name, size, and modified-date sorting.

## Settings Persistence

PulseFiles persists user preferences through its settings service, including:

- Last and startup directories for each pane.
- Sidebar visibility default.
- Experimental terminal enablement and default visibility.
- Single-pane mode preference.
- Hidden-file visibility default.
- Default sort descriptor.
- Confirmation preferences for copy, move, and delete workflows.
- Permanent-delete preference.
- Experimental sandbox preference.
- File color scheme.

Settings are stored with UserDefaults-backed app preferences, with import/export support where available in the app.

## Experimental Terminal V1

Terminal V1 is experimental, opt-in, and not a hardened shell environment or security boundary.

- It is disabled and hidden by default.
- Users must explicitly enable the experimental terminal setting before it can be shown or toggled by default.
- On first use, PulseFiles warns that shell commands can modify or delete files.
- The warning also communicates that shell commands may affect files outside the experimental sandbox when sandbox restrictions are disabled.
- The terminal working directory follows the active pane where possible.

## Sandbox and Access Model

PulseFiles is intended to behave like a normal file manager in release builds while still routing browsing and mutation decisions through its sandbox/access policy layer.

- Release builds are intended for broader normal file-manager disk access, subject to macOS permissions and user-granted access.
- DEBUG builds may use an experimental development sandbox rooted at `~/Library/Application Support/PulseFiles/ExperimentalSandbox`.
- The experimental sandbox can be enabled or disabled through supported launch arguments or persisted preferences in development builds.
- When experimental sandbox restrictions are enabled, navigation and file operations should remain inside the sandbox root unless the user explicitly grants access to an outside folder.
- External or user-provided locations should be validated through the sandbox file-access policy before browsing or mutating files.

## Known Limitations and Distribution Notes

- App Store sandbox distribution is not guaranteed by this draft. A Mac App Store build would need separate entitlement, bookmark, permission, and review-oriented configuration before it should be described as App Store sandbox ready.
- iCloud Drive, Desktop & Documents in iCloud, optimized-storage placeholders, conflict files, and cloud-provider sync states do not have special documented handling unless separately verified in testing.
- Network shares, removable drives, external volumes, mounted disk images, and custom filesystem providers may have edge cases that are not guaranteed unless explicitly tested.
- File permissions, extended attributes, package directories, symlinks, aliases, and provider-specific metadata should be verified for the specific release scenario before making preservation guarantees.
- Long-running operations and unusual failure modes may depend on macOS filesystem behavior, permissions prompts, and volume availability.
- Terminal V1 remains experimental and should not be presented as a hardened shell environment or security boundary.
- The DEBUG experimental sandbox is a development/testing safeguard, not a substitute for a production App Sandbox entitlement model.

## Suggested Release Body Summary

PulseFiles is a native AppKit dual-pane file manager for macOS 13+ focused on keyboard-first navigation, predictable file operations, active-pane search/filtering, configurable hidden-file visibility, and persisted user preferences. This release includes opt-in experimental terminal support with a first-use safety warning and an access model designed to keep DEBUG sandbox testing separate from normal release-build file-manager behavior.

