# PulseFiles

PulseFiles is a native, keyboard-first macOS file manager built with AppKit. It combines two independently navigable file panes, predictable file operations, fast keyboard commands, and native macOS integration in a focused alternative to Finder for people who prefer an orthodox dual-pane workflow.

## Development status

> [!WARNING]
> PulseFiles is under active development and is **not yet ready for general V1 use**. The current V1 candidate has broad core functionality, but signed-app release validation and the storage-provider compatibility matrix are still incomplete. Use it on backed-up, non-critical data and review the [release checklist](RELEASE_CHECKLIST.md) before treating a build as production-ready.

## Preview

<p align="center">
  <img src="PulseFiles/Resources/PulseFilesAppIconSource.png" alt="PulseFiles app icon" width="192">
</p>

The repository-owned app icon above ships with PulseFiles. Runnable debug and release bundles can be produced locally using the instructions below.

## Features

- Native AppKit interface with independent dual-pane navigation and per-pane tabs.
- Folder-first sortable file lists, breadcrumbs, search, hidden-file control, and multiple selection.
- Keyboard-driven copy, move, rename, trash, delete, folder creation, preview, and navigation.
- Conflict-aware, cancellable file operations with preflight checks and progress reporting.
- Sidebar shortcuts and recent locations, Quick Look, and a read-only text/hex viewer.
- Optional single-pane layout and an explicitly opt-in experimental terminal.

## System requirements

- macOS 13 Ventura or later.
- Swift 5.9 or later.
- Xcode or compatible Apple command-line developer tools.

## Install and launch

PulseFiles does not yet provide a generally available signed release. Build it from source:

```sh
git clone https://github.com/deemoun/PulseFiles.git
cd PulseFiles
./scripts/build_app.sh
open artifacts/PulseFiles.app
```

To build and launch in one step, run `./scripts/build_app.sh --run`. The debug bundle is written to `artifacts/PulseFiles.app`. For a local optimized but unsigned build, run `./scripts/build_release_app.sh --local-unsigned`; its development-only bundle is isolated at `artifacts/development/unsigned-release/PulseFiles.app`. Distributable packaging is a separate, credentialed workflow documented in `RELEASE_CHECKLIST.md`.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Tab | Switch the active pane |
| Return | Open the selected item, or confirm an edit |
| F3 | Open the selected file in the read-only text/hex viewer |
| F4 | Open the selected item normally |
| F5 / F6 | Copy / move the selection to the opposite pane |
| F7 / Shift-F7 | Create a folder / file |
| F8 / Shift-Delete | Move the selection to Trash |
| Space | Preview the selected item with Quick Look |
| Backspace / Command-Up | Navigate to the parent folder |
| Command-[ / Command-] | Navigate back / forward |
| Command-Shift-G | Go to a folder |
| Command-N / Command-Shift-N | Create a folder / file |
| Command-C / Command-X / Command-V | Copy / cut / paste |
| Command-Shift-. | Show or hide hidden files |
| Control-Command-1…7 | Sort by name, extension, kind, size, modified, created, or added date |
| Command-` | Toggle the Experimental Terminal after enabling it in Settings |
| Command-Period | Cancel the active file operation |
| Command-T / Command-W | Create / close a tab in the active pane |
| Control-Tab / Control-Shift-Tab | Select the next / previous tab in the active pane |
| Option-Command-\\ | Toggle single- and dual-pane layout |

The eighth sort criterion, **Accessed**, is available through menus and table headers but has no numbered shortcut.

## Safety model

### DEBUG experimental sandbox

Release builds use normal file-manager access, subject to macOS permissions and explicit folder grants. DEBUG builds can opt into a cautious restriction with `--pulsefiles-enable-experimental-sandbox`; while enabled, browsing and file operations remain under `~/Library/Application Support/PulseFiles/ExperimentalSandbox` unless access to another folder is explicitly granted. Access continues to route through the app's sandbox access policy in every build.

### Destructive operations

Copy, move, rename, trash, and permanent-delete operations are preflighted before mutation. PulseFiles validates sources and destinations, prompts for conflicts and configured confirmations, supports cancellation, and reports partial failures; nevertheless, test development builds only with backed-up, disposable data.

### Opt-in terminal

The Experimental Terminal is disabled and hidden by default. It must be enabled in Settings, shows a first-use warning, and is not a security boundary: commands can modify or delete any files that macOS permits the app to access. Cancellation terminates the process on a best-effort basis and cannot roll back commands that already ran.

Implementation details for these boundaries are in the [architecture and maintenance guide](DOCUMENTATION.md#filesystem-access-and-safety), and release scenarios are in the [release checklist](RELEASE_CHECKLIST.md).

## Version 1.0 storage compatibility

This table describes intended V1 behavior, not verified provider support. Conditional support must not be claimed until the corresponding signed-app scenarios have evidence in the [release checklist](RELEASE_CHECKLIST.md).

| Item class | V1 status | Behavior and recovery |
| --- | --- | --- |
| iCloud Drive and cloud-provider folders | Candidate behavior; signed-app verification pending | Browsing and normal operations use macOS access checks. A cloud-only iCloud item is intended to be rejected before mutation; download it in Finder and retry. Provider sync conflicts, provider-specific metadata, and providers without normal file semantics are not guaranteed. |
| Network shares and removable media | Candidate behavior; signed-app verification pending | Operations are intended to preflight and re-check availability before mutation. Reconnect or remount an unavailable volume and retry. Read-only media should be rejected with a writable-media recovery message. |
| Packages | Candidate behavior; signed-app verification pending | PulseFiles is intended to list packages as packages and copy or move their contents as a tree. Test application-specific package integrity before replacing production packages. |
| Symbolic links | Candidate behavior; signed-app verification pending | Copy is intended to preserve the stored link destination without resolving or traversing the target, preventing a link from reading an unselected external target. |
| Finder aliases | Not supported for mutation in V1 | PulseFiles detects a Finder alias before mutation and leaves it unchanged. Use Finder to manage the alias or operate on the original item. |
| Metadata preservation | Candidate best-effort behavior; signed-app verification pending | Copy paths are intended to preserve POSIX permissions, ownership IDs where permitted, timestamps, Finder tags and labels, extended attributes, and ACLs. If a destination rejects metadata, content should remain copied and PulseFiles should report a cleanup warning; verify metadata before removing the source. |

A successful content transfer does not guarantee preservation of cloud-provider state, custom metadata, or application-specific package internals.

## Development quick start

Run these commands from the repository root:

```sh
# Unit and in-process tests
swift test

# Package a local debug app at artifacts/PulseFiles.app
./scripts/build_app.sh

# Package an unsigned local optimized app (development only)
./scripts/build_release_app.sh --local-unsigned

# Sign, notarize, staple, verify, and archive a distributable release
PULSEFILES_SIGN_IDENTITY='Developer ID Application: …' \
PULSEFILES_NOTARY_PROFILE='pulsefiles-release' \
./scripts/build_release_app.sh --distribute

# Run the disposable automation entry point
./scripts/run_automation_tests.sh
```

On macOS hosts without Accessibility permission, use `./scripts/run_automation_tests.sh --skip-system-events` to retain Swift and in-process AppKit coverage while skipping the external System Events harness. Generated `.build/` and `artifacts/` content must not be committed. Detailed testing, packaging, and release-validation procedures live in [DOCUMENTATION.md](DOCUMENTATION.md#testing-builds-and-agent-checklist) and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).

## Architecture

PulseFiles is a Swift Package Manager executable organized by responsibility: `App` composes the window and menus; `FilePane`, `Sidebar`, and `Terminal` provide UI surfaces; `Commands` coordinates actions and shortcuts; `Services` owns persistence, access policy, filesystem loading, and operations; and `Models` and `Utilities` contain focused supporting types. See the [PulseFiles Architecture and Maintenance Guide](DOCUMENTATION.md) for the runtime flow and component reference.

## Roadmap

The [orthodox file-manager feature-gap audit](docs/orthodox-feature-gap-audit.md) tracks implemented behaviors, remaining V1 gaps, future directions, and explicitly deferred work.

## Contributing, testing, and project policies

- **Contributing:** Read [AGENTS.md](AGENTS.md) for repository conventions, safety constraints, and the change checklist, then open a focused pull request.
- **Testing:** Follow the [development quick start](#development-quick-start) and the detailed [testing guide](DOCUMENTATION.md#testing-builds-and-agent-checklist).
- **Privacy:** PulseFiles does not automatically upload diagnostics; read the [privacy policy](PRIVACY.md) for local data and permission details.
- **Support:** Use [GitHub Issues](https://github.com/deemoun/PulseFiles/issues) for support and [the issue chooser](https://github.com/deemoun/PulseFiles/issues/new/choose) for bug reports and feature requests.
- **License:** PulseFiles is available under the [GNU General Public License v3.0 or later](LICENSE); third-party attribution is listed in [NOTICE](NOTICE).
