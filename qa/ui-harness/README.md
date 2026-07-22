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

The harness creates a fresh temporary fixture root for every run and rejects
canonical source/destination paths outside that root. Some workflows deliberately
mutate only generated fixture files (for conflict, cancellation, trash, and
rename evidence); no workflow accepts a user-provided mutation path.

## Release sign-off limits

The harness is a signed-app smoke/evidence gate, not a replacement for the
full destructive matrix in `RELEASE_CHECKLIST.md`. Disk-image ejection timing,
privacy prompts, and manual drag gestures can require a reviewer on macOS.
Run those signed-release scenarios only with the generated fixture or another
fresh disposable location, retain the harness artifacts, and record any
UI-versus-service mismatch in the release handoff. Linux or unsigned-bundle
runs are never release sign-off.

## Reproducible disposable workflows and retained evidence

The harness now exposes individually selectable workflows rather than only a
confirmation smoke test. Run the complete set and retain its evidence with:

```sh
scripts/release_validation.sh \
  --signed-app artifacts/release/PulseFiles.app \
  --ui-artifacts-dir release-evidence/ui-$(git rev-parse --short HEAD)
```

Or focus a single workflow while diagnosing a release candidate:

```sh
qa/ui-harness/run_signed_app_ui_harness.sh artifacts/release/PulseFiles.app \
  --workflows copy-conflicts --artifacts-dir /tmp/pulsefiles-ui-evidence
```

See [WORKFLOWS.md](WORKFLOWS.md) for the navigation, search, conflict,
cancellation, drag/drop, trash, rename, grant recovery, volume fallback,
relaunch, and terminal workflows. The runner canonicalizes every mutation path
and rejects paths outside the newly-created fixture root; it never accepts a
user-provided source/destination path. When Accessibility automation is
available, `release_validation.sh` runs `--workflows all` and the retained
report, fixture tree snapshots, and screenshot are ready to attach to the
release-evidence record.
