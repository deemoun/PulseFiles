# Automation test cases

This document turns the current automation workflows into reviewable test
cases. It describes what each case exercises, how it is invoked, and the
safety boundary that applies while it runs. The executable sources of truth
remain [`scripts/run_automation_tests.sh`](../../scripts/run_automation_tests.sh),
[`run_debug_disposable_ui_runner.sh`](run_debug_disposable_ui_runner.sh), and
[`run_signed_app_ui_harness.sh`](run_signed_app_ui_harness.sh).

## Which command to run

Run the complete development automation flow from the repository root:

```sh
./scripts/run_automation_tests.sh
```

The entry point creates an isolated preferences home and an
`AutomationRun.*` fixture below the DEBUG experimental sandbox, enables the
DEBUG sandbox restriction, then runs these stages in order:

1. `swift test -c debug --filter PulseFilesTests`
2. On macOS, `swift test -c debug --filter PulseFilesAppKitUITests`
3. On macOS with Accessibility permission, the disposable System Events
   workflows listed below.

On a non-macOS host, stages 2 and 3 are skipped after the unit/service target
completes. On macOS CI without Accessibility permission, retain stages 1 and 2
and explicitly skip only stage 3:

```sh
./scripts/run_automation_tests.sh --skip-system-events
# equivalent: PULSEFILES_SKIP_SYSTEM_EVENTS=1 ./scripts/run_automation_tests.sh
```

The System Events cases require macOS and Accessibility permission for the
terminal or CI runner. They build a DEBUG app and use only runner-created
paths. The runner canonicalizes pane startup folders and every mutation source
or destination before launching the app, and deletes only its per-run fixture
and preferences directories during cleanup.

For release-signoff smoke evidence, use a **signed** app instead; this is a
separate, non-mutating flow:

```sh
scripts/release_validation.sh --signed-app artifacts/release/PulseFiles.app
```

Use `--artifacts-dir PATH` with either underlying UI harness to retain the
report, fixture snapshots, and final screenshot. See
[README.md](README.md) for runner prerequisites and
[WORKFLOWS.md](WORKFLOWS.md) for the concise workflow partition.

## Test cases

| ID | Workflow and execution | Expected result | Safety / evidence notes |
| --- | --- | --- | --- |
| AUTO-01 | **Unit and service suite** — stage 1 of `./scripts/run_automation_tests.sh`. | `PulseFilesTests` passes under disposable preferences and fixture paths. | Covers deterministic service and model behavior before external UI automation. |
| AUTO-02 | **AppKit controller wiring** — stage 2 on macOS. | `PulseFilesAppKitUITests` passes against the production AppKit controller tree and its accessibility identifiers. | In-process coverage; no System Events permission is needed for this stage. |
| AUTO-03 | **Navigation** — `navigation` in the DEBUG and signed-release UI runners. | The harness switches panes, moves through rows, and requests parent navigation without a UI automation failure. | Uses fixture startup folders only. |
| AUTO-04 | **Active-pane search** — `active-pane-search` in both UI runners. | After focus changes, searching for `needle-search` displays `needle-search.txt`. | The assertion reads the window accessibility content. |
| AUTO-05 | **Copy conflict handling** — `copy-conflicts` in both UI runners. | A conflict sheet appears and the harness chooses **Skip This Item**. | The signed-release flow remains non-mutating; the DEBUG flow is confined to its fixture. |
| AUTO-06 | **Move conflict handling** — `move-conflicts` in both UI runners. | A conflict sheet appears and the harness chooses **Cancel Whole Operation**. | The selected action prevents completion of the move. |
| AUTO-07 | **Transfer cancellation** — `cancellation` in the DEBUG runner only. | A copy of the generated 64 MiB fixture starts, then Command-Period requests cancellation. | Any source/destination is inside `AutomationRun.*`; this case is excluded from signed-release smoke. |
| AUTO-08 | **Drag/drop evidence point** — `drag-drop` in both UI runners. | The harness records the cross-pane accessibility interaction point without a UI automation failure. | This is a smoke/evidence anchor, not a completed filesystem transfer assertion. |
| AUTO-09 | **Rename** — `rename` in the DEBUG runner only. | `rename-me.txt` becomes `renamed-by-harness.txt`; the runner verifies that file exists afterward. | This is the only named completed mutation in the workflow table and is fixture-contained. |
| AUTO-10 | **Relaunch persistence** — `relaunch-persistence` in both UI runners. | The app quits and relaunches using the same isolated preferences home without a UI automation failure. | The test never reads or writes the developer's normal preferences. |
| AUTO-11 | **Terminal opt-in containment** — `terminal-opt-in-containment` in both UI runners. | The harness enables the terminal preference in isolated defaults, relaunches, and toggles the terminal UI. | It runs no arbitrary shell command. The terminal remains opt-in. |

## Release exclusions and manual coverage

The signed-release suite runs AUTO-03, AUTO-04, AUTO-05, AUTO-06, AUTO-08,
AUTO-10, and AUTO-11 only. It deliberately excludes completed copy/move,
cancellation, rename, permanent deletion, and Trash operations.

Neither System Events runner has a Trash workflow. `FileManager.trashItem` can
move an item into the system Trash, outside a fixture-root guard. Validate
production Trash and other destructive release scenarios manually with
equivalent OS-level isolation (a disposable account, VM, or disk image), using
the [destructive operations matrix](../destructive-mutating-operations-matrix.md)
and `RELEASE_CHECKLIST.md`.
