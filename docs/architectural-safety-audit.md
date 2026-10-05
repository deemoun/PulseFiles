# Architectural safety audit

This audit tracks evidence for safe native file-manager behavior. It does not
claim the application is free of every possible filesystem or provider race.
Changes in this worktree remain unverified by compilation and XCTest.

## Required guarantees and current evidence

| Guarantee | Implementation evidence | Verification still required |
| --- | --- | --- |
| All mutations remain behind the service boundary | Architecture validator passes; no presentation mutation exceptions | Full suite and disposable mutation harness |
| Filesystem authorization rejects non-file URLs in both modes | Guards in SandboxFileAccessPolicy; regression in services tests | Execute regression; inspect all URL entry routes |
| New destinations cannot silently replace an existing item | Descriptor rename uses RENAME_EXCL; staged transfers and archive publication carry replacement decisions | Race tests across transfers, extraction, rollback and supported providers |
| Failed replacement restoration preserves recovery data | Transfer and archive failure paths retain active staging records and report backup URLs | Execute restoration-failure and startup-cleanup tests |
| Cancellation does not allow overlapping window mutations | Detached workers keep mutation state active until completion; gate-based integration regression added | Execute cancellation-resistant worker test; multi-window/service ownership audit |
| Terminal requires explicit enablement and acknowledgement | Missing callback rejects startup; every input rechecks permission | Execute terminal tests; verify revocation, session termination and scope lifetime |
| Undo does not act on unrelated replacement items | Copy, move and rename recovery require stable destination identities | Execute identity regressions; close mutation-time identity window |
| Batch rename cycles can roll back | Published names are evacuated before originals are restored; identities checked | Execute cancellation and rollback-failure tests; preview-to-execution identity audit |
| Source reads do not follow a swapped final symlink or special file | Streaming copier opens parent components without following links, uses openat/O_NOFOLLOW and validates regular-file descriptor | Execute source-swap tests; cross-volume source cleanup and selected-identity audit |
| Archive extraction remains bounded and contained | Existing format, path, depth, byte and link validators | Audit parser and staging ownership; execute malicious archive matrix |

## Open engineering work

- Bind selected source identities and authorized parent descriptors to execution,
  especially cross-volume source removal, undo removal and rollback namespace calls.
- Verify replacement consent remains attached to the item whose identity the user
  approved, rather than any later object at that pathname.
- Check recursive staging cleanup and crash recovery preserve user content.
- Audit grant scope ownership through asynchronous reads and preview/open routes.
- Verify blocking policy probes cannot stall the main thread indefinitely.
- Verify commands, keyboard access, accessibility and localized recovery behavior.

## Validation limits

The architecture validator and whitespace checks pass. The active Command Line
Tools failed to resolve XCTest. Requests to run tests with installed Xcode and
subsequent builds were denied, so the current safety changes have not completed
build or runtime verification. Do not treat structural checks as a substitute.

Completion requires debug and release builds, the full five-target XCTest suite,
appropriate disposable automation, and review of every open guarantee above.

Search coordinator execution and result probes now use scoped authorization;
unauthorized-root regression coverage was added. Late errors from cancelled
search tasks are suppressed. Deadline-based probes can outlive their UI result,
so underlying worker scope lifetime still requires service-level verification.
