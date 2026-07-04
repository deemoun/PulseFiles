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
- Collapsible terminal/output area placeholder.
- Bottom command bar.
- Model, service, controller, view, command, and utility separation.
- Unit tests for navigation history, sorting, path utilities, and bookmark persistence.
- Experimental sandbox-root access flag defaults to enabled, limiting navigation to `~/Library/Application Support/PulseFiles/ExperimentalSandbox`.

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

Build and launch a release bundle:

```sh
./scripts/build_app.sh --release --run
```

The packaged app is written to `artifacts/PulseFiles.app`. You can also launch it manually:

```sh
open artifacts/PulseFiles.app
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
