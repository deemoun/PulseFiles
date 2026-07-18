# PulseFiles

PulseFiles is a native macOS AppKit file manager scaffolded for a fast, keyboard-first, dual-pane workflow.

## Current Phase

Phase 1 is implemented:

- AppKit application entry point and main window.
- Unified toolbar with back, forward, search, terminal, sidebar, view, and settings controls.
- Dual independently loading `NSTableView` file panes.
- Breadcrumb headers with clickable path components.
- Native file icons and `Name`, `Size`, and `Modified` columns.
- Folder-first sorting with sortable table headers.
- Directory navigation by double-click, Return, Backspace, and Command-Up.
- Active-pane switching with Tab.
- Right shortcuts/recent sidebar.
- Terminal V1 is experimental, hidden by default, and requires the explicit “Enable experimental terminal” setting before it can be shown.
- Bottom command bar.
- Model, service, controller, view, command, and utility separation.
- Unit tests for navigation history, sorting, path utilities, and bookmark persistence.
- Release builds default to normal file-manager access behavior, subject to macOS permissions and any user-granted folders. DEBUG builds are unrestricted by default too, but can opt into the experimental sandbox with `--pulsefiles-enable-experimental-sandbox` or the `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` UserDefaults key. When that flag is enabled, browsing and file operations are restricted to `~/Library/Application Support/PulseFiles/ExperimentalSandbox` unless the user explicitly grants access to an outside folder.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Tab | Switch pane |
| Return | Open the selected item, or rename/confirm text when editing |
| Backspace / Command-Up | Navigate to the parent folder |
| Command-[ / Command-] | Navigate back / forward |
| Command-Shift-G | Go to folder |
| Command-N / Command-Shift-N | Create a new folder / file |
| Command-C / Command-X / Command-V | Copy / cut / paste with the clipboard |
| Command-Shift-. | Show or hide hidden files |
| Command-` | Toggle Terminal V1 after enabling it in Settings |
| Command-Period | Cancel the active file operation |

## Experimental sandbox access

Release builds default to normal file-manager access behavior: PulseFiles is not restricted to its experimental sandbox by default, and access is governed by macOS permissions plus any folders the user explicitly grants.

DEBUG builds also default to unrestricted normal file-manager behavior. For development and testing, launch a DEBUG build with `--pulsefiles-enable-experimental-sandbox` or set the `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` UserDefaults key to `true` to restrict browsing and file operations. `--pulsefiles-disable-experimental-sandbox` forces the restriction off. In release builds, `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` resolves to `false`; persisted sandbox preferences are ignored/removed by settings import/export behavior.

When `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` is enabled in DEBUG, PulseFiles creates and uses this root:

```text
~/Library/Application Support/PulseFiles/ExperimentalSandbox
```

Restricted DEBUG browsing and file operations should stay inside that root unless the user explicitly grants an outside folder through the app's access policy flow.

## Terminal V1 status

The integrated terminal is a V1 experimental feature. It is hidden and disabled by default. To use it, open Settings and enable **Enable experimental terminal**; optionally enable **Show terminal by default** after that. On first use, PulseFiles warns that shell commands can modify or delete files, including files outside the app's experimental sandbox when sandbox restrictions are disabled.

## Version 1.0 storage compatibility

The following is the 1.0 product commitment, not a promise that every third-party filesystem provider implements identical macOS behavior. Final release sign-off for the supported rows is performed against a signed app using the scenarios in `RELEASE_CHECKLIST.md`.

| Item class | 1.0 status | Behavior and recovery |
| --- | --- | --- |
| iCloud Drive and cloud-provider folders | Supported when the item is locally available and the provider allows the operation | Browsing and normal operations use macOS access checks. A cloud-only iCloud item is rejected before mutation; download it in Finder and retry. Provider sync conflicts, provider-specific metadata, and providers that do not expose normal file semantics are not guaranteed. |
| Network shares and removable media | Supported while mounted, reachable, writable, and permitted by macOS | Operations are preflighted and re-check availability before mutation. A disconnected volume is reported as unavailable; reconnect/remount it and retry. Read-only media is rejected with a writable-media recovery message. |
| Packages | Supported as directory trees | PulseFiles lists packages as packages and copies/moves their contents as a tree. Test application-specific package integrity before replacing production packages. |
| Symbolic links | Supported as links | Copy preserves the stored link destination without resolving or traversing the target. This prevents a link from reading an unselected external target. |
| Finder aliases | Not supported for mutation in 1.0 | PulseFiles detects a Finder alias before mutation and leaves it unchanged. Use Finder to manage the alias or operate on the original item. Finder aliases are not symbolic links. |
| Metadata preservation | Best-effort support | Copy paths preserve POSIX permissions, ownership IDs where permitted, timestamps, Finder tags/labels, extended attributes, and ACLs. If a destination/provider rejects metadata, content remains copied but PulseFiles reports a cleanup warning; verify metadata on the destination before removing the source. |

Do not treat a successful file-content transfer as a guarantee that cloud-provider state, custom metadata, or application-specific package internals were preserved. These limits are intentionally reflected in the release-facing copy rather than hidden behind a generic "all files" claim.

## Opening

Open the repository folder or `Package.swift` in Xcode. The local environment used to create this project only has Command Line Tools active, so full Xcode project generation/build verification was left for a machine with Xcode selected.

## Build Notes

Build a local test `.app` bundle:

```sh
./scripts/build_app.sh
```

Build and launch the test bundle:

```sh
./scripts/build_app.sh --run
```

Build and launch a release bundle (unsigned by default, with signing flags reserved for future distribution):

```sh
./scripts/build_release_app.sh --run
```

The debug app is written to `artifacts/PulseFiles.app`, while the release app is written to `artifacts/release/PulseFiles.app`. You can also launch them manually:

```sh
open artifacts/PulseFiles.app
open artifacts/release/PulseFiles.app
```

The Swift package target is named `PulseFiles` and uses AppKit directly. The source tree is organized to mirror the planned Xcode project structure:

- `PulseFiles/App`
- `PulseFiles/Models`
- `PulseFiles/Services`
- `PulseFiles/FilePane`
- `PulseFiles/Sidebar`
- `PulseFiles/Terminal`
- `PulseFiles/Commands`
- `PulseFiles/Utilities`
- `PulseFilesTests`
