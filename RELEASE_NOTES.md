# PulseFiles 1.0.0-beta.1 Testing Notes

<!-- release-version: 1.0.0-beta.1; build-number: 1 -->

PulseFiles **1.0.0-beta.1** (build **1**) is a prerelease for testing, not a
production-ready 1.0 release. **Use it only with backed-up, non-critical data.**
Do not rely on this beta as the only way to access or preserve important files.
The customer-facing marketing version and monotonically increasing build number
are defined in `release/VERSION`.

## What to test

Try dual-pane navigation, keyboard workflows, conflict and cancellation paths,
and operations on disposable local fixtures. If you can safely exercise a cloud
provider, network share, removable volume, package, or symbolic link, report the
exact environment and outcome. Review or file beta findings in the
[PulseFiles issue tracker](https://github.com/deemoun/PulseFiles/issues); use the
[issue chooser](https://github.com/deemoun/PulseFiles/issues/new/choose) for a
new report.

## Support, privacy, and feedback

- **Support:** export a reviewable bundle from **Help → Export Diagnostics…**,
  then open a support request at <https://github.com/deemoun/PulseFiles/issues>.
- **Privacy policy:** <https://github.com/deemoun/PulseFiles/blob/main/PRIVACY.md>.
- **Report an issue:** <https://github.com/deemoun/PulseFiles/issues/new/choose>.

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

### Undo guarantees

- The enabled Undo menu item names the precise recoverable action: **Undo Copy**, **Undo Move**, **Undo Rename**, or **Undo Move to Trash**.
- Undo Copy removes only a fully completed, non-replacement copy destination after PulseFiles verifies the platform resource identity captured when it was created. If the identity, volume, access, or provider state cannot be verified, Undo is unavailable and nothing is removed.
- Undo Move and Undo Rename retain their collision, access, and writable-destination safeguards. Undo Move to Trash restores only the item returned by macOS's trash API, after the same identity and destination checks.
- Permanent deletion, replacements, skipped/failed/cancelled or partial operations, cleanup warnings, and uncertain provider states are explicitly non-undoable.

## Search, Filtering, and Hidden Files

- Search/filter applies to the active pane.
- Search mode hides the synthetic parent row (`..`) so filtered results do not expose unintended navigation shortcuts.
- Hidden files can be shown or hidden, including a persisted default preference for hidden-file visibility.
- File listings preserve folder-first sorting behavior while supporting name, size, and modified-date sorting.

## Settings Persistence

PulseFiles persists user preferences through its settings service, including:

- Last and startup directories for each pane.
- Sidebar visibility default.
- Experimental Terminal enablement and default visibility.
- Single-pane mode preference.
- Hidden-file visibility default.
- Default sort descriptor.
- Confirmation preferences for copy, move, and delete workflows.
- Permanent-delete preference.
- Experimental sandbox preference.
- File color scheme.

Settings are stored with UserDefaults-backed app preferences, with import/export support where available in the app.

## Experimental Terminal

The Experimental Terminal is an opt-in feature, not a supported shell environment or security boundary.

- It is disabled and hidden by default; its menu, toolbar, shortcut help, settings, and in-panel label use the Experimental Terminal label.
- Users must explicitly enable the Experimental Terminal setting before it can appear.
- A command launches through the configured shell in the active pane directory only after `SandboxFileAccessPolicy` authorizes that directory; an unavailable or unauthorized directory falls back to the policy root or is rejected before launch.
- The Experimental Terminal holds any security-scoped folder access only for the command lifetime, streams bounded combined output and error text, reports startup errors and non-zero exit statuses, and cleans up its output handler and access scope at completion.
- Hiding the panel or tearing down the window sends best-effort termination to the active process. This is cancellation only, not rollback; commands can leave partial or destructive filesystem changes.
- First use requires acknowledgement that shell commands can modify or delete files macOS permits PulseFiles to access, including granted folders when experimental restrictions are disabled.

## Sandbox and Access Model

PulseFiles is intended to behave like a normal file manager in release builds while still routing browsing and mutation decisions through its sandbox/access policy layer.

- Release builds default to broader normal file-manager disk access, subject to macOS permissions and user-granted access; they are not restricted to the experimental sandbox by default.
- DEBUG builds also default to unrestricted normal file-manager behavior, but can opt into the experimental development sandbox with `--pulsefiles-enable-experimental-sandbox` or the `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` UserDefaults key.
- `--pulsefiles-disable-experimental-sandbox` forces `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` off; in release builds the flag resolves to `false`, and release settings import/export does not preserve the debug-only sandbox preference.
- The experimental sandbox root is `~/Library/Application Support/PulseFiles/ExperimentalSandbox`.
- When experimental sandbox restrictions are enabled in DEBUG, navigation and file operations should remain inside the sandbox root unless the user explicitly grants access to an outside folder.
- External or user-provided locations should be validated through the sandbox file-access policy before browsing or mutating files.

## Known Limitations and Distribution Notes

- **Release-verification status:** this beta has not completed
  the required signed-app matrix on macOS, Apple Silicon, and Intel. The cloud,
  network-share, removable-media, package, symbolic-link, and metadata behaviors
  below are implementation expectations, not verified support claims, until the
  signed candidate has passing evidence for the corresponding release-checklist
  scenarios. Do not publish them as supported before that sign-off.
- App Store sandbox distribution is not guaranteed by this draft. A Mac App Store build would need separate entitlement, bookmark, permission, and review-oriented configuration before it should be described as App Store sandbox ready.
- **Cloud-provider folders (verification pending):** intended for items that macOS reports as locally available and accessible. A cloud-only iCloud item should be rejected before mutation with instructions to download it in Finder and retry. Sync conflicts, provider-specific metadata, and providers that do not offer normal file semantics are not guaranteed.
- **Network shares and removable media (verification pending):** intended to work while mounted, reachable, writable, and allowed by macOS. A removed/disconnected volume should be rejected before mutation where detectable and ask the user to reconnect or remount it; read-only destinations should be rejected with a writable-media recovery message.
- **Packages (verification pending):** intended to behave as directory trees for browsing, copy, move, rename, trash, and deletion. Application-specific package validity remains the owning application's responsibility, so release QA uses disposable package fixtures.
- **Symbolic links (verification pending):** intended to be handled as links. Copy should store the original link destination rather than resolving or traversing it, so a selected link does not cause an unselected external target to be copied.
- **Finder aliases:** not supported for mutation in 1.0. PulseFiles detects Finder aliases before mutation where macOS identifies them and leaves them unchanged; users should use Finder to manage the alias or operate on its original item. An alias is not a symbolic link.
- **Metadata (verification pending):** content transfers are intended to make a best-effort attempt to preserve permissions, ownership IDs where permitted, timestamps, Finder tags/labels, extended attributes, and ACLs. A metadata failure should be surfaced as a cleanup warning rather than silently claimed as complete; users must verify destination metadata before deleting the source. Provider-specific metadata is not guaranteed.
- Long-running operations and unusual failure modes may depend on macOS filesystem behavior, permissions prompts, and volume availability.
- The Experimental Terminal is opt-in and must not be presented as a supported shell environment or security boundary.
- The DEBUG experimental sandbox is a development/testing safeguard, not a substitute for a production App Sandbox entitlement model.

## Suggested Beta Release Body Summary

PulseFiles 1.0.0-beta.1 is a prerelease AppKit dual-pane file manager for macOS 13+ focused on keyboard-first navigation, predictable file operations, active-pane search/filtering, configurable hidden-file visibility, and persisted user preferences. Test only with backed-up, non-critical data. Storage-provider, package, symbolic-link, and metadata behavior remains unverified until the signed-app release matrix passes and must not be presented as supported. Finder alias mutation and provider-specific cloud metadata are not supported promises. The Experimental Terminal remains opt-in and clearly labeled while DEBUG sandbox testing stays separate from normal release-build file-manager behavior.
