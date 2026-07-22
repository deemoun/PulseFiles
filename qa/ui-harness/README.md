# PulseFiles UI automation

PulseFiles keeps disposable DEBUG mutation automation separate from signed
release-signoff validation.

## Signed-release smoke suite

`run_signed_app_ui_harness.sh` drives a signed release `PulseFiles.app` through
System Events. It verifies signing and Accessibility automation, creates
fixture-only startup paths and isolated preferences, then runs **non-mutating**
smoke workflows only. Copy and move confirmation checks explicitly select Skip
or Cancel; it never completes copy/move, renames, deletes, or invokes Trash.

```sh
scripts/release_validation.sh --signed-app artifacts/release/PulseFiles.app
```

The signed-app suite remains an evidence gate, not a substitute for the manual
destructive matrix in `RELEASE_CHECKLIST.md`. Production Trash is excluded:
`FileManager.trashItem` can move a fixture source into the OS Trash, which is
not contained by a fixture-root guard. Perform signed-release destructive QA
only with equivalent OS-level isolation such as a disposable account, VM, or
disk image, and retain the result in release evidence.

## DEBUG disposable automation runner

Run the mutation-capable automation through the safe repository entry point:

```sh
./scripts/run_automation_tests.sh
```

`scripts/release_validation.sh` is release evidence only: its signed-app suite
is non-mutating. It runs the DEBUG mutation runner only when explicitly given
`--run-debug-mutation-harness`, and that opt-in run is not release evidence.

The underlying DEBUG runner builds the DEBUG app itself, launches it with
`--pulsefiles-enable-experimental-sandbox`, and uses an isolated HOME. The
runner creates a fresh `AutomationRun.*` child beneath that configured
experimental sandbox root. Before launch, it canonicalizes and rejects any
pane startup path or mutating source/destination outside that child. It accepts
no app, source, or destination path argument. It exercises fixture-contained
rename and cancellation behavior, but intentionally has no Trash workflow.

Use `--artifacts-dir PATH` to retain logs, tree snapshots, and screenshots, or
`--keep-fixture` to inspect the isolated HOME after a run. See
[WORKFLOWS.md](WORKFLOWS.md) for the exact workflow partition.

## Prerequisites

Both runners require macOS and Accessibility permission for the invoking
terminal or CI runner. The signed runner additionally requires a valid signed
bundle (`codesign --verify --deep --strict`). Linux and unsigned-bundle runs
are never signed-release sign-off.
