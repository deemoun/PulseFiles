# PulseFiles Scenarios 6–8, 10, 15, and 16 — Linux Host Blocker

This is an attempted validation record, **not pass evidence**. The requested
scenarios require the same signed release candidate running on macOS. The
available host is Linux, and neither a signed candidate nor the macOS signing,
AppKit, Finder, provider, volume, and Accessibility facilities are present.
No operation was performed and no compatibility row is promoted to supported.

## Candidate and environment

| Field | Value |
| --- | --- |
| Candidate source SHA | `35a75fa5326973b1e3376b4434a51f90cf4abeb3` (source state before this evidence-only commit) |
| Release metadata | `1.0.0-beta.1`, build `1` |
| Test date | 2026-10-01 UTC |
| Host | Linux 6.18.44, x86_64 |
| Swift | 6.1.3, target `x86_64-unknown-linux-gnu` |
| Signed candidate | **Unavailable.** Candidate discovery found no `.app`, `.dmg`, or `.pkg`. `./scripts/build_release_app.sh --clean --sign` exited 64 because no signing identity was supplied. `codesign`, `spctl`, `sw_vers`, `diskutil`, `hdiutil`, `mdls`, `xattr`, and `osascript` are unavailable. |
| Disposable fixture root | Not created: a Linux filesystem fixture would not exercise the signed AppKit application or macOS access/provider semantics. |
| Mounted/provider media | Container overlay plus virtual `proc`, `tmpfs`, `devpts`, and `cgroup2` mounts only; no cloud provider, network share, macOS disk image, or removable media. |
| Overall result | **Not run — release blocker.** |

The request to reuse one signed candidate cannot be met by substituting an
unsigned or DEBUG build. There is therefore no candidate signature, bundle
hash, notarization/stapling result, or app screenshot to attach.

## Requested scenario results

| Scenario | Result | Evidence and required signed-macOS rerun |
| --- | --- | --- |
| 6 — copy, move, rename, Trash, permanent delete | **Not run — blocker.** | Create isolated source/destination fixtures and sentinels. Retain before/after trees, hashes, metadata, confirmations, screenshots, and visible results for valid/invalid rename, Trash, permanent delete, partial failure, undo, and cleanup warnings. Prove every unselected sentinel is unchanged. |
| 7 — replacement, skip, cancel | **Not run — blocker.** | Exercise distinguishable file and directory conflicts. Record destination/source hashes before and after each choice, queued-item disposition, undo availability/result, visible result, and replacement-failure recovery. |
| 8 — operation cancellation | **Not run — blocker.** | Use sufficiently large disposable trees for deterministic in-progress cancellation. Record progress and result screenshots, completed/incomplete item state, cleanup warnings, and hashes for unrelated sentinels. |
| 10 — security-scoped grants | **Not run — blocker.** | Requires the signed app, a protected ungranted folder, folder picker, bookmark persistence across relaunch, revoked-grant recovery, and inside/outside boundary sentinels. Confirm every denied attempt causes zero writes. |
| 15 — mounted-volume changes | **Not run — blocker.** | Requires a writable disposable macOS volume, read-only remount, and eject during a multi-item operation. Capture mount details, sidebar/pane fallback, partial result, cleanup warning, and before/after trees. |
| 16 — storage compatibility | **Not run — blocker.** | Every requested fixture combination remains unverified; the per-fixture matrix below is the mandatory rerun plan. |

Because no scenario ran, copy, move, rename, Trash, permanent delete,
replacement, skip, cancellation, undo, partial failures, and cleanup warnings
have **not** been confirmed for this candidate. Likewise, this record cannot
confirm that operations leave every unselected item unchanged or remain inside
an authorized access boundary. Both properties remain release-blocking checks.

## Scenario 16 fixture matrix

| Fixture | Required operations/evidence | Result |
| --- | --- | --- |
| Locally available provider item | Copy and move with provider identity/state, trees, hashes, metadata, screenshots, and result. | **Not run:** no macOS provider account. |
| Cloud-only provider item | Attempt before download, prove zero mutation, capture recovery message; download in Finder and retry with the same signed candidate. | **Not run:** no Finder or provider account. |
| Disposable network share | Writable browse/copy/move/rename/Trash, disconnected retry, partial failure/cleanup result, protocol/filesystem/mount details. | **Not run:** no disposable share or macOS mount client. |
| Writable/read-only/ejected removable media | Copy both directions, read-only rejection, eject-before and eject-during-operation cases, remount recovery, mount flags and trees. | **Not run:** no macOS disk image/removable media tools. |
| Package tree | Copy/move/rename/Trash/open/reveal; compare complete package trees, file hashes, metadata, and results. | **Not run:** signed AppKit app unavailable. |
| Relative symbolic link | Copy and move; retain `readlink` output and external-target sentinel hashes. | **Not run in signed app.** |
| Absolute symbolic link | Copy and move; retain stored absolute destination and prove target was not traversed. | **Not run in signed app.** |
| Broken symbolic link | Copy and move without resolving it; retain `readlink` and source/destination trees. | **Not run in signed app.** |
| Cyclic/self-referential symbolic links | Copy and move without traversal, hang, or mutation outside the selection. | **Not run in signed app.** |
| Real Finder alias | Attempt copy/move/rename/Trash/permanent delete; prove preflight rejection and unchanged alias, target, and destination. | **Not run:** Finder alias APIs unavailable. Mutation remains documented as unsupported. |
| Permissions and timestamps | Same-filesystem and cross-provider copies; compare `stat -x` before/after and capture warnings. | **Not run on macOS.** |
| Finder tags and extended attributes | Compare `xattr -lr` before/after on local, network, and removable destinations. | **Not run:** representative macOS xattrs/provider semantics unavailable. |
| ACLs | Compare `ls -le@` before/after where each destination supports ACLs; capture cleanup warnings and retain source until verified. | **Not run on macOS.** |

For every originating rerun, also capture the macOS version/build, hardware,
candidate SHA and signature, provider item state, filesystem, mount protocol and
flags, visible operation result, and screenshots. Use a no-follow tree walk plus
a separate `readlink` pass so evidence collection itself does not traverse test
links. Hash external targets, alias targets, and unselected boundary sentinels
before and after every mutation. Retain sources whenever metadata preservation
or destination integrity is uncertain.

## Retained artifact inventory

| Requested artifact | Retained result |
| --- | --- |
| Before/after fixture trees | None; no qualifying fixture could be created or exercised. |
| Content hashes/link destinations | None; no qualifying signed-app operation ran. |
| Metadata output | Host capability/mount inventory only; no representative macOS metadata fixture. |
| Mount/provider details | Linux container mounts recorded above; no qualifying provider or media. |
| Screenshots | None; the AppKit app cannot launch on this host. |
| Visible operation results | None; no operation was initiated. |

The absence of artifacts is not interpreted as a pass. It documents why the
requested evidence must be collected on the originating signed-macOS rerun.

## Automated checks and defects

| Command | Outcome |
| --- | --- |
| `./scripts/validate_architecture.sh` | **Pass (exit 0).** This is a source architecture check, not signed-app scenario evidence. |
| `./scripts/build_release_app.sh --clean --sign` | **Blocked (exit 64):** `--sign-identity` / `PULSEFILES_SIGN_IDENTITY` was unavailable; no signed candidate was produced. |
| `swift test` | **Failed before tests ran (exit 1):** the Linux build cannot import `Darwin`; it also reports an existing access-level mismatch where public `PaneArrangementRoute` exposes package-scoped `PaneID`. This does not establish any requested scenario result. |
| `scripts/release_validation.sh --signed-app artifacts/release/PulseFiles.app` | **Not completed:** the initial combined attempt did not reach signed-app validation, and the candidate path does not exist. |

No defect was discovered by exercising the requested scenarios because none
could run. Consequently there is no truthful originating scenario to reproduce,
no focused regression test to add, and no rebuilt signed candidate to retest.
The compile diagnostics above are recorded as pre-existing validation blockers,
not as defects observed in scenarios 6–8, 10, 15, or 16.

## Compatibility and release decision

`README.md` and `RELEASE_NOTES.md` continue to mark cloud/provider folders,
network/removable media, packages, symbolic links, and metadata preservation as
unverified, and Finder alias mutation as unsupported. This attempt provides no
evidence that could safely broaden those claims; the documents are intentionally
unchanged.

**Decision: BLOCKED.** Do not use this record to sign off scenarios 6–8, 10,
15, or 16. Supply one signed candidate and rerun the entire matrix with isolated
macOS fixtures, retaining all listed artifacts. If a defect is found, add a
focused automated regression, rebuild and re-sign that candidate, and repeat
the originating scenario before considering it passed.
