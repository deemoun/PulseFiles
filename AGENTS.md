# AGENTS.md - PulseFiles Contributor Guide

## Scope and precedence

These repository-root instructions apply to every file in PulseFiles unless a
deeper `AGENTS.md` provides more specific instructions for its subtree. Direct
user and system instructions always take precedence over any `AGENTS.md`.

## Project identity

PulseFiles is a native macOS 13+ AppKit file manager built with Swift Package
Manager. Preserve its fast, keyboard-first, independently navigable dual panes.
Do not introduce a SwiftUI rewrite unless explicitly requested. Release builds
behave as a normal file manager; DEBUG builds may opt into a cautious
experimental sandbox. Keep models, services, controllers/views, commands, and
utilities separated. See [DOCUMENTATION.md](DOCUMENTATION.md) for the detailed
architecture and maintenance guide.

## Repository map

- `Package.swift` declares the `PulseFiles` executable and four SwiftPM test
  targets: `PulseFilesCoreTests`, `PulseFilesServicesTests`, `PulseFilesTests`,
  and `PulseFilesAppKitUITests`.
- `PulseFiles/App`, `FilePane`, `Sidebar`, and `Terminal` contain AppKit lifecycle,
  window composition, pane browsing, secondary navigation, and the opt-in terminal.
- `PulseFiles/Commands`, `Models`, `Services`, and `Utilities` contain command
  routing, value types, filesystem/persistence services, and shared helpers.
- `PulseFiles/Settings` contains preferences UI; `PulseFiles/Debug` contains
  DEBUG-oriented diagnostics UI; `PulseFiles/Resources` contains packaged assets.
- `PulseFilesCoreTests` contains AppKit-free utility and model tests;
  `PulseFilesServicesTests` covers filesystem, access-policy, and persistence
  services; and `PulseFilesTests` covers application and cross-layer integration
  behavior. `PulseFilesTests/TestSupport` documents shared test-support conventions.
- `PulseFilesAppKitUITests` contains in-process AppKit wiring and accessibility
  tests.
- `qa` contains the destructive-operation matrix, evidence templates, and the
  [QA harness documentation](qa/ui-harness/README.md); `docs` contains focused
  product and engineering decisions.
- `scripts` contains build, automation, versioning, and release-validation tools.
- `RELEASE_CHECKLIST.md`, `RELEASE_NOTES.md`, and `release/VERSION` are the release
  checklist, release notes, and canonical version metadata. Follow
  [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) rather than duplicating release
  procedures here.

## Before editing

- Inspect the working tree with `git status --short` and review relevant diffs
  before changing files.
- Treat existing modifications as user work: do not overwrite, reformat, stage,
  revert, or otherwise touch unrelated changes.
- Never commit generated `.build/` or `artifacts/` content.
- Read the nearby implementation, tests, and any deeper `AGENTS.md` before editing.

## Verification matrix

Run the narrowest relevant checks from the repository root, expanding coverage
for cross-cutting, runnable-app, or release changes.

| Command | Use |
| --- | --- |
| `./scripts/validate_architecture.sh` | Enforce package-layer dependency and filesystem-mutation boundaries. |
| `swift test` | Run all four SwiftPM test targets. |
| `./scripts/run_automation_tests.sh` | Run the disposable automated suite, including the macOS System Events mutation harness. |
| `./scripts/run_automation_tests.sh --skip-system-events` | Run the disposable Swift and in-process AppKit coverage where Accessibility automation is unavailable. |
| `./scripts/build_app.sh` | Build the local DEBUG app bundle. |
| `./scripts/build_release_app.sh` | Build the release app bundle. |
| `scripts/release_validation.sh --signed-app PATH/TO/PulseFiles.app` | Produce macOS signed-release validation evidence; requires a valid signed app and Accessibility automation. |

The package uses Swift tools 5.9. Build scripts use isolated SwiftPM paths under
`.build` and emit bundles under `artifacts`; neither directory belongs in commits.

## Architecture and safety rules

- Keep cross-pane coordination in `MainWindowViewController` and single-pane
  loading, sorting, filtering, and history in `FilePaneViewModel` and its pane
  controller. Keep menus, `MainCommand`, command routing, command bar, keyboard
  handling, localization, and tests consistent when adding a command.
- Use `FileOperationService` for **all filesystem mutations**. Never mutate the
  filesystem directly from UI code. Preserve preflight validation, explicit
  replace/skip/cancel conflict handling, cancellation, progress, and partial-result
  reporting; never overwrite silently.
- Route **every external or user-provided URL** through
  `SandboxFileAccessPolicy` before browsing or mutation, in DEBUG and release.
  Never bypass the policy. Restricted DEBUG navigation and operations must remain
  within the experimental root unless access was explicitly granted.
- The integrated terminal remains experimental, opt-in, disabled and hidden by
  default, with its first-use risk warning intact.
- Persist preferences through typed `SettingsService` properties rather than raw
  scattered `UserDefaults` keys.
- Keep UI-facing view models, state changes, and callbacks on the appropriate
  `@MainActor` boundary. Keep slow filesystem operations asynchronous where the
  existing design does so.
- Use native, restrained programmatic AppKit and existing styling helpers. Provide
  accessible names, labels/tooltips, identifiers where tested, and keyboard access
  for UI controls. Do not steal standard text-input shortcuts.
- Write Swift 5.9-compatible code, prefer focused `final` types, direct imports,
  dependency injection for testable logic, and avoid unjustified force unwraps or
  new global mutable state.

## Completion checklist

Before handoff:

1. Review the final diff and working tree; confirm unrelated user changes and
   generated `.build`/`artifacts` output are not included.
2. Run relevant checks from the verification matrix and add or update focused
   XCTest/AppKit/automation coverage for changed behavior and safety boundaries.
3. Update relevant documentation and localized user-facing strings when behavior,
   commands, settings, safety guidance, or release procedures change.
4. For UI changes, verify accessibility labels/identifiers, keyboard behavior, and
   appropriate accessibility test or QA coverage.
5. Confirm external URLs still pass through `SandboxFileAccessPolicy`, sandbox and
   terminal safeguards remain intact, and no direct UI filesystem mutation was
   introduced outside `FileOperationService`.
6. In the handoff summary, state user-visible behavior, sandbox/terminal/destructive
   operation safety implications, the exact commands run, and every environmental
   limitation or skipped check.
