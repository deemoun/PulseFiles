# PulseFiles signed-app UI harness

This folder contains an external macOS UI harness for release validation. It drives a built, signed `PulseFiles.app` with `System Events` instead of SwiftPM/XCTest so the same app bundle that users receive is exercised.

## What it covers

`run_signed_app_ui_harness.sh` creates disposable source and destination folders, writes PulseFiles startup preferences to point both panes at those folders, launches the supplied app bundle, and checks these release-critical flows:

- app launch and close-last-window termination
- active pane switching with Tab
- keyboard navigation with arrow keys and Command-Up
- search/filter using the toolbar search shortcut
- sidebar visibility entry points
- command bar invocation and dismissal
- terminal disabled state, then enabled state after an explicit preference flip
- copy, move, and delete confirmation entry points using disposable files, cancelling each prompt to prove the harness does not mutate real user data; each flow now fails unless its confirmation sheet was actually displayed

## Prerequisites

1. Run on macOS with a signed app bundle. The harness fails if `codesign --verify --deep --strict` does not pass.
2. Grant Accessibility permission to the terminal or CI runner that invokes the script: **System Settings → Privacy & Security → Accessibility**.
3. Build and sign the release bundle, for example:

   ```sh
   ./scripts/build_release_app.sh --clean --sign --sign-identity "Developer ID Application: Example Corp (TEAMID)"
   ```

## Running directly

```sh
qa/ui-harness/run_signed_app_ui_harness.sh artifacts/release/PulseFiles.app
```

If no path is supplied, the script uses `artifacts/release/PulseFiles.app`.

## Release validation integration

The repository-level release validation wrapper can run the harness after command-line tests and release packaging:

```sh
scripts/release_validation.sh --signed-app artifacts/release/PulseFiles.app
```

Use `--skip-ui-harness` only for non-macOS automation or environments that cannot grant Accessibility automation. A final release candidate should still run this harness on a signed app before publication.

## Safety notes

The harness only creates and targets folders under a temporary directory. Destructive operation dialogs are opened and cancelled, and the script verifies the disposable source files still exist after the confirmation-flow checks.

## Sections 6–8 and 15 release sign-off

The signed-app harness is a smoke gate, not a replacement for the destructive
manual scenarios in `RELEASE_CHECKLIST.md`. In particular, it deliberately
cancels its confirmation sheets and therefore does **not** mutate data to test
multi-item transfers, conflict choices, permanent deletion, in-flight
cancellation, or volume ejection. Run those scenarios against a signed release
bundle on macOS using a disposable directory and disk image/external volume,
then record the outcome (including any UI-versus-service mismatch) in the
release handoff. Do not treat a Linux or unsigned-bundle run as sign-off.

The confirmation smoke coverage intentionally stays on the initial disposable
pane instead of navigating to Home before it runs. It also asserts that every
requested destructive action produced a sheet; this prevents a missing
selection or a navigation regression from being reported as a successful
cancelled-operation check.
