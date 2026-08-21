# PulseFiles Scenario 16 Evidence — Linux Host Blocker

This is an attempted Scenario 16 validation record, **not pass evidence**. The
checklist requires a signed release app on macOS. The available host is Linux,
so it cannot produce or launch a signed AppKit app, create a Finder alias, use
iCloud/Finder metadata, or mount representative macOS providers and media.
No combination below is promoted to supported status.

## Candidate and environment

| Field | Value |
| --- | --- |
| Candidate source SHA | `c0c7499ed4359ffd934b9527d969cdddf88577cb` (candidate before the fix/evidence commit) |
| Test date | 2026-08-21 UTC |
| Host | Linux 6.18.35, x86_64 |
| Swift | 6.1.3, target `x86_64-unknown-linux-gnu` |
| Signed app | Unavailable; `./scripts/build_release_app.sh --clean --sign` exited 64 because no signing identity was available |
| macOS/provider fixtures | Unavailable |
| Result | **Not run — release blocker** |

## Requested fixture and operation matrix

| Fixture or boundary | Requested coverage | Result and required follow-up |
| --- | --- | --- |
| Cloud | Locally downloaded and cloud-only items; copy and move; download/retry | **Not run.** Requires a dedicated macOS provider account and Finder. Record provider and item download state on the signed-app rerun. |
| Network share | Writable browse/copy/move/rename/trash, then disconnected retry | **Not run.** Requires a disposable SMB/NFS share. Record protocol, filesystem, and before/after share trees. |
| Removable media | Writable copy both directions; read-only destination; ejected source/destination | **Not run.** Requires a macOS disk image or disposable media. Record mount flags and before/after trees. |
| Package | Copy/move/rename/trash/open/reveal and tree comparison | **Not run.** Requires the signed AppKit app and a disposable package fixture. |
| Symbolic links | Relative, absolute, broken, external-target, and cyclic links; copy and move | **Not run in the signed app.** The rerun must record `readlink` output and prove no unselected external target content appears at the destination. |
| Finder alias | Copy/move/rename/trash/permanent delete; alias and target unchanged | **Static defect found and fixed:** service tests previously expected all five mutations to succeed, contradicting the checklist and public compatibility boundary. Provider-independent tests now require preflight rejection and unchanged fixtures. A real Finder alias still requires signed-app retest. |
| Metadata | Permissions, timestamps, Finder tags, xattrs, ACLs on same-filesystem and cross-provider copies | **Not run.** Linux cannot provide representative Finder tags/resource forks or macOS provider behavior. Record `stat`, `xattr -lr`, `ls -le@`, and destination warnings on macOS. |
| Unavailable/read-only recovery | Cloud download, reconnect/remount, and writable-media guidance before mutation | **Not run in UI.** Existing injectable service coverage could not execute because this macOS package imports Darwin/AppKit. Confirm messages and zero destination writes in the signed app. |

## Before-and-after tree and metadata record

No provider fixtures were created because doing so on Linux would not exercise
the required signed-app/macOS boundaries. Consequently there are no truthful
before/after provider trees or metadata snapshots to attach. On the originating
macOS rerun, attach for every fixture:

1. `find -H FIXTURE -xdev -print` before and after (use a separate `readlink` pass;
   do not follow test links when proving traversal safety).
2. `stat -x`, `ls -le@`, and `xattr -lr` output for each source and destination.
3. Provider/filesystem/protocol, mount flags, macOS build, app SHA/signature, UI
   error screenshots, and operation-result warnings.
4. Target-side sentinel hashes for external and alias targets before and after.

## Defect and regression disposition

**PF-S16-ALIAS-001 — Finder alias mutation contract contradicted release docs.**
The injected Finder-alias tests demonstrated that copy, move, rename, trash, and
permanent delete were intentionally allowed as opaque-object mutations. Scenario
16 requires rejection before mutation. The preflight now emits a dedicated
Finder-alias error with Finder/original-item guidance, and regression tests cover
all five operations, conflict handling, and unchanged alias/target/destination
fixtures without depending on a provider.

The originating signed-app Finder-alias scenario was **not repeated** because no
signed macOS app can run on this host. This remains a release blocker until the
fixed commit is signed and the complete operation set passes against an actual
Finder alias.

## Commands attempted

| Command | Outcome |
| --- | --- |
| `./scripts/build_release_app.sh --clean --sign` | **Blocked (exit 64):** signing identity unavailable; no signed app produced. |
| `swift test` | **Blocked (exit 1):** package compilation fails on Linux at `import Darwin`; tests did not execute. |

## Compatibility reconciliation and release decision

`README.md` and `RELEASE_NOTES.md` already label cloud, network/removable,
packages, symbolic links, and metadata as verification pending, and Finder alias
mutation as unsupported. Those conservative boundaries remain accurate, so no
support row was promoted or softened.

**Decision: BLOCKED.** Repeat all Scenario 16 rows with disposable fixtures on
the required signed macOS candidate and attach the evidence listed above before
release sign-off.
