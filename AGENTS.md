# AGENTS.md - PulseFiles Contributor Guide

This file gives AI coding agents the project-specific context needed to make changes safely and consistently in PulseFiles. It applies to the entire repository.

## Project identity

PulseFiles is a native macOS AppKit file manager built with Swift Package Manager. It is intended to be a fast, keyboard-first, dual-pane file manager. Release builds should behave like a normal file manager; DEBUG builds may use a cautious experimental sandbox for development and testing.

Core product goals:

- Keep the app native to macOS and AppKit; do not introduce SwiftUI rewrites unless explicitly requested.
- Preserve a keyboard-first workflow with dual independently navigable panes.
- Make file operations predictable, confirmable, and safe.
- Keep experimental or potentially destructive behavior opt-in and clearly communicated.
- Maintain a clean separation among models, services, controllers/views, commands, and utilities.

## Repository layout

- `Package.swift` defines a SwiftPM executable target named `PulseFiles` and a test target named `PulseFilesTests`.
- `PulseFiles/App` contains the application entry point, app delegate, main menus, and main window composition.
- `PulseFiles/FilePane` contains the dual-pane browser UI, table view behavior, breadcrumbs, status display, and pane view model.
- `PulseFiles/Sidebar` contains shortcuts and recent-location UI.
- `PulseFiles/Terminal` contains the experimental integrated terminal UI.
- `PulseFiles/Commands` contains menu/command-bar command modeling and shortcut coordination.
- `PulseFiles/Services` contains persistence, filesystem loading, bookmarks/recent locations, sandbox access policy, directory monitoring, terminal execution, and file operations.
- `PulseFiles/Models` contains pure value types such as file items, pane state, operation models, bookmarks, and navigation history.
- `PulseFiles/Utilities` contains small reusable helpers, formatters, styling, filename validation, experimental flags, and icon/color helpers.
- `PulseFiles/Resources` contains app resources such as `AppIcon.icns`.
- `PulseFilesTests` contains XCTest coverage for utilities, sorting, navigation history, bookmarks, and file operations.
- `scripts/build_app.sh` builds and packages a local `.app` bundle in `artifacts/PulseFiles.app`.

## Build and test commands

Prefer these commands from the repository root:

```sh
swift test
./scripts/build_app.sh
./scripts/build_app.sh --release
./scripts/build_app.sh --run
```

Notes:

- The package uses Swift tools version 5.9 and targets macOS 13 or newer.
- `scripts/build_app.sh` uses isolated SwiftPM cache/config/security paths under `.build` and copies `PulseFiles/Info.plist` and resources into an app bundle.
- Do not commit generated `.build/` or `artifacts/` output unless the user explicitly asks for generated artifacts.

## Architecture and behavior expectations

### Application lifecycle and menus

- `AppDelegate` owns the main menu, app icon setup, and the main window controller.
- Menu items are wired to `MainWindowViewController` selectors. When adding user-facing actions, update the menu, `MainCommand` if applicable, command bar behavior if applicable, and tests where possible.
- The app should terminate after the last window closes.

### Main window composition

`MainWindowViewController` coordinates the major UI surfaces:

- Left and right `FilePaneViewController` instances.
- Optional sidebar with bounded width.
- Optional experimental terminal panel.
- Bottom command bar.
- Toolbar search/filter state, active-pane state, split-view layout, and high-level command execution.

Keep cross-pane orchestration in `MainWindowViewController`. Keep single-pane filesystem or table behavior in `FilePaneViewController` / `FilePaneViewModel`.

### File panes

Each pane is independently navigable and should retain these behaviors:

- Folder-first file listing with sortable `Name`, `Size`, and `Modified` columns.
- Breadcrumb navigation through path components.
- Multiple selection.
- Double-click / Return opens directories or files.
- Backspace and Command-Up navigate to parent where allowed.
- Tab switches active pane.
- Active pane is visually indicated and receives search filtering.
- The synthetic parent row (`..`) should not appear while search is active and must not allow navigation outside the active sandbox root.

Use `FilePaneViewModel` for loading, sorting, hidden-file toggling, search filtering, and navigation history. UI controllers should not duplicate filesystem sorting/loading logic.

### Sandbox and file access

Release builds are intended to be full normal file-manager builds. The experimental sandbox is a DEBUG-only development/testing safeguard rooted at:

```text
~/Library/Application Support/PulseFiles/ExperimentalSandbox
```

Important rules:

- `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` defaults to `false` in release builds. In DEBUG builds it can be enabled with `--pulsefiles-enable-experimental-sandbox` or the `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` UserDefaults key, and disabled with `--pulsefiles-disable-experimental-sandbox`.
- When DEBUG sandbox mode is enabled, navigation and file operations should stay inside `ExperimentalFlags.appSandboxRoot` unless the user explicitly grants access to a specific outside folder through `SandboxFileAccessPolicy`.
- Always validate external or user-provided URLs through `SandboxFileAccessPolicy` before browsing or mutating files.
- Do not bypass `SandboxFileAccessPolicy` in new code.
- In release builds, broader disk access is expected for a normal file manager, but code should still route access through `SandboxFileAccessPolicy` so macOS permissions and explicit folder grants are handled consistently.

### File operations

Use `FileOperationService` for copy, move, rename, trash, and permanent delete behavior. Preserve these safeguards:

- Preflight operations before mutation.
- Reject empty selections, duplicate sources, duplicate destinations, missing sources, invalid destination directories, and destination-inside-source moves/copies.
- Validate sandbox access for both sources and destinations.
- Resolve conflicts with replace/skip/cancel instead of overwriting silently.
- For replacement, keep behavior safe if replacement cannot be completed.
- Report partial failures, cleanup warnings, skipped items, and cancellation via `FileOperationResult`.
- Keep long-running operations async and report progress through the existing progress handler model.

### Terminal behavior

The integrated terminal is experimental and must remain opt-in:

- It is disabled and hidden by default.
- `SettingsService.experimentalTerminalEnabled` must be true before the terminal can be shown by default or toggled.
- On first use, the app warns that shell commands can modify/delete files and may affect files outside the experimental sandbox when restrictions are disabled.
- Terminal working directory follows the active pane where possible.

Do not make terminal features enabled by default without an explicit user request.

### Settings persistence

`SettingsService` wraps `UserDefaults`. Use it for persisted app preferences such as:

- Last/startup directories for each pane.
- Sidebar and terminal default visibility.
- Single-pane mode.
- Hidden-file default.
- Default sort descriptor.
- Confirmation preferences for copy/move/delete.
- Permanent delete preference.
- Experimental sandbox preference.
- File color scheme.

When adding settings, prefer typed computed properties in `SettingsService` over scattered raw `UserDefaults` keys.

### Visual style

- The app uses AppKit views programmatically rather than nib/storyboard files.
- Prefer existing styling helpers in `LiquidGlassStyle` for panels, buttons, and window background.
- Keep the UI native and restrained. Use SF Symbols where appropriate.
- Maintain accessible labels/tooltips for icon-only controls.

### Commands and keyboard behavior

- `MainCommand` is the central high-level command enum.
- Keep menu actions, toolbar actions, command bar actions, and keyboard shortcuts consistent.
- If adding a command, consider every entry point: main menu, command bar, keyboard handling, active pane routing, and tests.
- Avoid stealing standard text input shortcuts from search fields or dialogs.

### Tests

Add or update XCTest coverage when changing logic in:

- `FileOperationService`
- `FileSystemService` sorting/filtering behavior
- `NavigationHistory`
- `BookmarkService` / persistence
- `FileNameValidator`
- Path or formatting utilities
- Sandbox access rules

UI-only AppKit changes may be harder to test, but still run `swift test` when possible.

## Coding conventions

- Write Swift 5.9-compatible code for macOS 13+.
- Keep imports simple and direct. Never wrap imports in `do`/`catch` or other error-handling blocks.
- Prefer `final` for classes that are not intended to be subclassed.
- Prefer small focused types and extensions over large unrelated utility dumping grounds.
- Respect `@MainActor` boundaries for UI-facing view models and UI callbacks.
- Keep filesystem work and potentially slow operations asynchronous where existing patterns do so.
- Use dependency injection for filesystem/service collaborators in testable logic.
- Avoid force unwraps in production code unless the invariant is obvious and documented by surrounding code.
- Avoid introducing global mutable state except for existing app-level settings/flags patterns.
- Keep user-facing strings clear, concise, and safety-oriented for destructive operations.

## Change checklist for agents

Before finishing a change:

1. Confirm the change preserves sandbox constraints and does not accidentally expose real filesystem mutation by default.
2. Confirm new commands are wired through all relevant UI entry points.
3. Confirm persisted preferences go through `SettingsService`.
4. Confirm file operations use `FileOperationService` instead of direct `FileManager` mutation from UI controllers.
5. Run `swift test` if the environment supports it.
6. Run `./scripts/build_app.sh` for runnable app changes when practical.
7. Do not commit build artifacts from `.build/` or `artifacts/`.

## PR / handoff notes

When summarizing changes, mention:

- User-facing behavior changes.
- Safety implications for sandboxing, terminal, or destructive file operations.
- Tests/build commands run and whether failures are environmental.
