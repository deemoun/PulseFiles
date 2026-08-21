# PulseFiles destructive mutation QA — blocked host record

This record documents the requested destructive-operation validation attempt
for candidate `c0c7499ed4359ffd934b9527d969cdddf88577cb`. It is **not pass
evidence**. The available host was Linux, not a disposable macOS account, VM,
or disk image, and no signed release app was supplied or present.

## Environment and candidate

| Field | Value |
| --- | --- |
| Test date (UTC) | 2026-08-21 |
| Candidate SHA | `c0c7499ed4359ffd934b9527d969cdddf88577cb` |
| Source version/build | 1.0.0 / 1 |
| Host | Linux 6.18.35, x86_64 |
| Swift | 6.1.3, target `x86_64-unknown-linux-gnu` |
| Required macOS tools | `osascript`, `hdiutil`, `codesign`, and `screencapture` unavailable |
| Signed app | Not supplied; no `PulseFiles.app` found under `artifacts/` |
| Disposable macOS isolation | Unavailable |

## DEBUG mutation harness attempt

The requested command was invoked with an evidence directory outside the
repository:

```sh
qa/ui-harness/run_debug_disposable_ui_runner.sh \
  --artifacts-dir /tmp/PulseFiles-QA-20260821-debug-evidence
```

It exited with status 1 at its platform guard and reported:

```text
2026-08-21T01:53:48Z FAIL: Requires macOS System Events automation.
```

The retained report contained only that failure. The runner stopped before
building or launching PulseFiles and before creating or mutating its pane
fixtures. Therefore it produced no before/after trees, hashes, operation
results, cleanup warnings, or screenshots, and none of its mutation workflows
may be marked passed.

## Requested signed-app destructive scenarios

| Scenario | Outcome | Required follow-up on macOS |
| --- | --- | --- |
| Conflict Replace / Skip / Cancel | **Not run — release blocker** | Exercise each decision for copy and move, retaining both source and destination hashes and result summaries. |
| Copy, move, and rename | **Not run — release blocker** | Run single- and multi-item operations from the supported UI entry points and capture before/after trees and hashes. |
| Trash and permanent delete | **Not run — release blocker** | Use OS-level disposable isolation; record confirmation UI, Trash recoverability, and permanent-delete results. |
| Supported Undo paths | **Not run — release blocker** | Verify every advertised Undo route and capture the restored tree and contents. |
| Multi-item partial failure | **Not run — release blocker** | Inject one failure after a successful item and verify completed, skipped, and failed result accounting. |
| Cancellation during a large transfer | **Not run — release blocker** | Cancel an in-progress copy and cross-volume move; record partial destination cleanup and source integrity. |
| Destination cleanup failure | **Not run — release blocker** | Inject cleanup failure and verify a visible cleanup warning and understandable source/destination state. |
| Same-volume move | **Not run — release blocker** | Run on a disposable APFS volume and verify destination contents before confirming source removal. |
| Cross-volume move | **Not run — release blocker** | Use two disposable APFS disk images and verify copy-before-source-removal behavior. |
| Volume disconnection during transfer | **Not run — release blocker** | Disconnect only a disposable image during transfer and record the error, partial result, and cleanup state. |

## Integrity assertions

The following release-critical assertions remain **unverified**, rather than
failed, because no operation reached the app:

- Replace never silently loses both source and destination.
- A rejected operation creates no destination.
- Unrelated files remain byte-for-byte unchanged.
- Cancellation and partial failures accurately report completed work and any
  cleanup warnings.
- All mutations stay behind `FileOperationService` and all external access
  decisions stay behind `SandboxFileAccessPolicy` in the exercised binary.

No product defect was observed, so no focused regression test or code fix was
added. Consequently there is no replacement candidate SHA to build or retest.
This candidate must not be signed off until the entire requested matrix is run
against the signed app on suitable disposable macOS infrastructure, with the
evidence required by `qa/release-evidence-template.md` attached.

**Release decision: BLOCKED — do not ship based on this record.**
