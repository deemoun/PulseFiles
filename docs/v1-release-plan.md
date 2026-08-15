# PulseFiles V1 completion plan

## Objective and definition of done

V1 is a **release-validation milestone**, not a request to add every feature in
the orthodox feature audit. The product surface needed for V1 is already broad;
the remaining work is to turn the current candidate behavior into verified,
supportable behavior on a signed macOS application.

V1 is ready only when all of the following are true:

1. A single release-candidate commit passes the automated suite and packaging
   checks without source changes between validation runs.
2. The app built from that commit is Developer ID signed, hardened, notarized,
   stapled, Gatekeeper accepted, and distributed with a verified archive digest.
3. The required macOS, architecture, clean-account, and storage-provider matrix
   in `RELEASE_CHECKLIST.md` has complete evidence.
4. Every failure found in that matrix is fixed and regression-tested, or is an
   explicitly approved limitation with an owner, target release, and accurate
   customer-facing release-note text.
5. Release notes, README support claims, rollback ownership, and the final
   release decision match the evidence rather than the intended implementation.

The plan does not promote the optional competitive follow-ups or explicitly
post-V1 features in `orthodox-feature-gap-audit.md` into release blockers.

## Current baseline

- Core dual-pane navigation, selection, search, common file operations, tabs,
  viewer, archive slice, settings, and safety routing are implemented and have
  Swift/in-process test coverage.
- Signing, notarization, packaging, security-evidence capture, and UI-harness
  scripts exist.
- The only repository evidence record is a Linux blocked-host record. It is
  useful proof that unsupported-host attempts were not treated as passes, but it
  supplies none of the signed macOS evidence required for V1.
- Cloud-provider, network-share, removable-media, package, symbolic-link,
  Finder-alias, and metadata behavior remains candidate behavior until the
  signed-app matrix passes.
- The CI workflow is currently manual (`workflow_dispatch`) and covers only a
  macOS 14 / Swift 5.9 automation run. This is useful presubmit evidence, but it
  is not the release OS/architecture matrix.

## Execution order

### P0 — Establish a reproducible candidate

**Goal:** produce one immutable SHA that is worth spending signed-macOS test time
on.

1. Run from a clean checkout:
   - `swift test`
   - `./scripts/run_automation_tests.sh --skip-system-events`
   - `./scripts/test_release_packaging.sh`
   - `./scripts/build_app.sh`
   - `./scripts/build_release_app.sh --local-unsigned`
2. Enable branch/pull-request execution for the CI-safe automation workflow, or
   add an equivalent required presubmit workflow. Keep release credential use
   out of untrusted pull-request jobs.
3. Record the chosen full SHA and verify `release/VERSION`, release-note version,
   build number, bundle metadata, and generated app metadata agree.
4. Freeze feature work on the candidate. Any fix found later creates a new SHA,
   invalidates evidence tied to the superseded binary, and restarts the affected
   validation rows.

**Exit criteria:** all local/CI-safe checks pass on the recorded SHA, clean and
unsigned bundles build, no generated `.build` or `artifacts` content is tracked,
and a release manager owns the candidate.

### P0 — Build and attest the distributable artifact

**Goal:** prove that the artifact users would receive is the artifact that was
tested.

1. On an approved macOS release host, install the approved Developer ID
   Application identity and notarization profile.
2. Run `./scripts/build_release_app.sh --distribute` from the candidate SHA.
3. Run `scripts/release_validation.sh` against the produced signed app with
   explicit security-evidence and UI-artifact paths.
4. Retain the authority chain, hardened-runtime result, notarization/Gatekeeper
   result, staple validation, archive digest, candidate SHA, and harness output
   together in the release record.
5. Install and launch the archived product outside SwiftPM to catch staging,
   resource, localization, icon, or bundle-only failures.

**Exit criteria:** every security and packaging field in the evidence template
passes, the ZIP digest verifies, and the signed app is traceable to the frozen
candidate SHA.

### P0 — Complete the signed-app behavioral matrix

**Goal:** validate the file manager where unit tests cannot reproduce macOS,
provider, permission, and mounted-volume behavior.

Use one copied `qa/release-evidence-template.md` record per OS/architecture
combination. Cover macOS 13, 14, 15, and the current supported macOS release,
with at least one Apple Silicon and one Intel run. Include a clean user account.
For the first public V1, where no prior PulseFiles release exists, test migration
from the oldest repository-supported V1 settings fixture or pre-release build and
record that substitution explicitly; after V1, require upgrade from the
immediately prior public release.

Run the full manual checklist, prioritizing these data-integrity boundaries:

1. Replace, skip, cancel, partial failure, and cleanup-warning behavior.
2. Mid-operation cancellation and volume disconnect, including source and
   destination integrity after interruption.
3. Trash, permanent delete, conservative undo, and rejection of unsafe or
   ambiguous requests.
4. Security-scoped grant persistence/revocation and release unrestricted mode.
5. Terminal opt-in, first-use warning, authorized working directory, command
   termination, and disabled-on-relaunch behavior.
6. Clean-launch, relaunch persistence, navigation, selection, keyboard focus,
   accessibility, and bundle-only integrations such as Quick Look/Open With.

**Exit criteria:** every scenario has a pass/fail result and evidence; “not run”
is not a pass. No unresolved destructive-operation, access-policy, terminal, or
data-integrity failure may be downgraded to a limitation merely to ship V1.

### P0 — Complete storage-provider compatibility

**Goal:** replace candidate claims with measured support boundaries.

Use disposable fixtures and record before/after trees and relevant metadata for:

- locally downloaded and cloud-only provider items;
- writable and disconnected network shares;
- writable, read-only, and ejected removable media or disk images;
- packages;
- relative, absolute, broken, external-target, and cyclic symbolic links;
- Finder aliases; and
- same-volume and cross-provider metadata preservation.

For every defect, add the narrowest reproducible automated test that can run
without the provider, then repeat the original signed-app scenario. Expected
environmental limitations must produce actionable recovery text and no
unintended mutation. Do not broaden README or release-note support claims beyond
the combinations actually evidenced.

**Exit criteria:** every storage row passes or has an approved, accurately worded
limitation. Symbolic links never traverse an unselected target, aliases remain
unchanged when rejected, unavailable/read-only providers fail before unsafe
mutation, and metadata loss is reported rather than silently treated as success.

### P1 — Fix findings without weakening safety

Fixes discovered during P0 should follow this order:

1. data loss, unintended overwrite/delete, or mutation outside the selected set;
2. sandbox/access-policy bypass or leaked security-scoped access;
3. crash, hang, cancellation failure, or corrupt partial output;
4. incorrect result/cleanup reporting or misleading recovery guidance;
5. broken keyboard, accessibility, persistence, or common navigation behavior;
6. visual polish and non-blocking compatibility limitations.

All filesystem fixes must remain behind `FileOperationService` and
`SandboxFileAccessPolicy`, preserve explicit conflict choices and partial-result
reporting, and include focused regression coverage. Do not solve a release defect
with a UI-side filesystem mutation, silent fallback, unbounded traversal, or by
enabling the Experimental Terminal by default.

**Exit criteria:** fixes have regression tests, affected signed scenarios pass on
a newly built candidate, and evidence references the replacement SHA/artifact.

### P1 — Release readiness and handoff

1. Review all evidence and populate named owners, rollback contact, previous
   known-good artifact (or “no prior public release” for V1), rollback steps, and
   communication location.
2. Reconcile `README.md`, `RELEASE_NOTES.md`, privacy/support links, and known
   limitations with the final matrix.
3. Run the final checklist against the distributable ZIP, not an unsigned or
   SwiftPM-launched build.
4. Obtain release-manager sign-off only after every blocker is closed.

**Exit criteria:** the release checklist is complete, limitations are approved
and customer-visible, rollback responsibility is assigned, and the published
archive is the signed/notarized artifact whose digest and behavior were recorded.

## Explicitly deferred from V1

Do not delay V1 solely for a true Gallery grid, orthodox multi-column Brief mode,
general archive codecs, advanced-search UI, broader batch-rename language, Empty
Trash, remote/virtual providers, a process panel, administrator mode, or external
tool templates. These remain valid post-V1 work unless validation shows that an
existing V1 route is unsafe or materially misleading.

## Release decision rule

Ship only when every P0 exit criterion passes on the same candidate artifact and
all P1 release-readiness work is complete. Otherwise the decision remains
**blocked**. The absence of a reproduced defect is not equivalent to evidence of
a pass, and implementation intent is not a substitute for signed-app validation.
