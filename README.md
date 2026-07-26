# PulseFiles

PulseFiles is a native macOS AppKit file manager scaffolded for a fast, keyboard-first, dual-pane workflow.

## Current Phase

Phase 1 is implemented:

- AppKit application entry point and main window.
- Unified toolbar with back, forward, search, a clearly labeled Experimental Terminal, sidebar, view, and settings controls.
- Dual independently loading `NSTableView` file panes.
- Breadcrumb headers with clickable path components.
- Native file icons and `Name`, `Size`, and `Modified` columns.
- Folder-first sorting with sortable table headers.
- Directory navigation by double-click, Return, Backspace, and Command-Up.
- Active-pane switching with Tab.
- Right shortcuts/recent sidebar.
- The Experimental Terminal is hidden by default and requires the explicit “Enable Experimental Terminal” setting before it can be shown.
- Bottom command bar.
- Model, service, controller, view, command, and utility separation.
- Unit tests for navigation history, sorting, path utilities, and bookmark persistence.
- Release builds default to normal file-manager access behavior, subject to macOS permissions and any user-granted folders. DEBUG builds are unrestricted by default too, but can opt into the experimental sandbox with `--pulsefiles-enable-experimental-sandbox` or the `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` UserDefaults key. When that flag is enabled, browsing and file operations are restricted to `~/Library/Application Support/PulseFiles/ExperimentalSandbox` unless the user explicitly grants access to an outside folder.

## License

PulseFiles is licensed under the [GNU General Public License v3.0 or later](LICENSE) (`GPL-3.0-or-later`). Redistributions of modified versions must provide the corresponding source code under that license.

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
| Control-Command-1…7 | Sort by name, extension, kind, size, modified date, created date, or added date |
| Command-` | Toggle the Experimental Terminal after enabling it in Settings |
| Command-Period | Cancel the active file operation |
| Command-T / Command-W | Create / close a tab in the active pane |
| Control-Tab / Control-Shift-Tab | Select the next / previous tab in the active pane |
| Option-Command-\\ | Toggle single- and dual-pane layout |

## Experimental sandbox access

Release builds default to normal file-manager access behavior: PulseFiles is not restricted to its experimental sandbox by default, and access is governed by macOS permissions plus any folders the user explicitly grants.

DEBUG builds also default to unrestricted normal file-manager behavior. For development and testing, launch a DEBUG build with `--pulsefiles-enable-experimental-sandbox` or set the `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` UserDefaults key to `true` to restrict browsing and file operations. `--pulsefiles-disable-experimental-sandbox` forces the restriction off. In release builds, `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` resolves to `false`; persisted sandbox preferences are ignored/removed by settings import/export behavior.

When `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` is enabled in DEBUG, PulseFiles creates and uses this root:

```text
~/Library/Application Support/PulseFiles/ExperimentalSandbox
```

Restricted DEBUG browsing and file operations should stay inside that root unless the user explicitly grants an outside folder through the app's access policy flow.

## Experimental Terminal policy

The Experimental Terminal is an opt-in feature, not a security boundary or a supported shell environment. It is hidden and disabled by default. Every visible entry point uses the **Experimental Terminal** label; to try it, enable **Enable Experimental Terminal** in Settings, then optionally enable **Show Experimental Terminal by default**.

The Experimental Terminal runs a non-interactive shell command in the active pane folder when that folder is authorized by `SandboxFileAccessPolicy`; otherwise it falls back to the policy root or rejects the launch. It keeps the applicable access scope only while the command runs, streams bounded combined output/error text, reports startup and non-zero-exit failures in the panel, and terminates the active process when the panel is removed or the window is torn down. Cancellation is best-effort process termination, not a transactional rollback: shell commands may already have changed files. First use requires acknowledgement that commands can modify or delete files that macOS permits PulseFiles to access, including security-scoped folder grants when sandbox restrictions are disabled.

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

Run the complete automated test suite through the safe disposable entry point:

```sh
./scripts/run_automation_tests.sh
```

It isolates preferences and all mutation-capable DEBUG UI fixtures, enables the
experimental sandbox for DEBUG UI automation, and skips AppKit UI automation on
non-macOS hosts. Release evidence remains separate in
`scripts/release_validation.sh`; its DEBUG mutation harness is opt-in.

For non-destructive macOS CI, retain the Swift unit and in-process AppKit UI
coverage while skipping the external System Events mutation harness (which
requires Accessibility permission):

```sh
./scripts/run_automation_tests.sh --skip-system-events
# Or: PULSEFILES_SKIP_SYSTEM_EVENTS=1 ./scripts/run_automation_tests.sh
```

Without this option or environment variable, the System Events runner remains
enabled for local macOS automation.

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

## Export diagnostics for support

Choose **Help → Export Diagnostics…** and select a destination folder. PulseFiles creates a timestamped `PulseFiles-Diagnostics-…` folder locally; it does not collect or upload diagnostics automatically. Review the included `diagnostics.txt` and `REDACTION_POLICY.txt`, then attach the folder (or a zip you create from it) to your support request along with a description of what happened.

The export includes app/version/build and macOS information, sanitized in-memory diagnostic entries, and count-only summaries of recent file-operation results. It excludes filesystem paths, security-scoped bookmark data, clipboard contents, terminal commands/output, and password/token/secret/credential/API-key values. Entries categorized as Terminal, Clipboard, or Bookmark are excluded entirely.

## Support, privacy, and issue reporting

- **Support:** use **Help → Get Support** or file a support request at <https://github.com/deemoun/PulseFiles/issues>.
- **Privacy policy:** use **Help → Privacy Policy** or read [PRIVACY.md](PRIVACY.md).
- **Issue reporting:** use **Help → Report an Issue** or open <https://github.com/deemoun/PulseFiles/issues/new/choose>.

## File sorting

Each pane remembers its own sort key, direction, text comparison mode, and folder-first preference. The eight sort criteria are **Name, Extension, Kind, Size, Modified, Created, Added, and Accessed**. Selecting the current criterion again reverses its direction; folder-first grouping, when enabled, remains in force in either direction. Missing date metadata is shown as `--` and ordered consistently.

The authoritative shortcut range requested for sorting contains seven keys, so Control-Command-1 through Control-Command-7 map in the order shown above to Name through Added. **Accessed is the eighth criterion and intentionally remains menu/table-header only**; it is not silently omitted from the product, assigned an overlapping shortcut, or allowed to displace an existing shortcut.
