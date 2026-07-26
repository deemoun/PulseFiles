# PulseFiles Signed Release Evidence — Blocked Host Record

This record uses the fields from `qa/release-evidence-template.md`. It records
an attempted validation, not a release pass. No manual scenario was marked
passed because the available host is Linux rather than supported macOS hardware.

## Release and environment

| Required field | Value |
| --- | --- |
| Release version | 1.0.0 |
| Build number | 1 |
| Build SHA (full commit SHA) | `9b444b61718d7f8a4757bbbd6ff2ac88fdf1f9a3` (candidate before this evidence-only commit) |
| Signed app path, signing identity, and notarization/stapling status | Intended path: `artifacts/release/PulseFiles.app`; no app produced; signing identity unavailable; not notarized or stapled |
| Tester (name or team alias) | Codex |
| Test date (UTC) | 2026-07-26 |
| macOS version and build number | Not available — Linux 6.12.13 host |
| Hardware architecture (Apple Silicon or Intel) | Neither qualifying target; Linux x86_64 |
| Test account | Container user; not a disposable macOS account |
| Install path | Not installed |
| Install type (clean install or upgrade from prior version) | Not run |
| Prior app version/build/SHA (required for upgrade) | Not available |
| Upgrade result | Not run; previous persisted-settings schema could not be exercised |
| Reset/fixture details and disposable test location | No mutation fixtures created because OS-level isolation and macOS APIs were unavailable |
| Release notes/support/privacy/issue links reviewed | Repository documents reviewed; provider claims changed to verification-pending language |

## Required coverage

| Target | macOS build | Architecture | Clean user account | Upgrade from prior release | Evidence record link | Status |
| --- | --- | --- | --- | --- | --- | --- |
| macOS 13 | Not run | Not run | Not run | Not run | This record | **Not run — blocker** |
| macOS 14 | Not run | Not run | Not run | Not run | This record | **Not run — blocker** |
| macOS 15 | Not run | Not run | Not run | Not run | This record | **Not run — blocker** |
| Current macOS release (state version) | Not run | Not run | Not run | Not run | This record | **Not run — blocker** |

Apple Silicon, Intel, clean-install, and prior-schema upgrade coverage remain
unverified and block release sign-off.

## Build and automated validation attempts

| Command | Outcome | Evidence |
| --- | --- | --- |
| `./scripts/build_release_app.sh --clean --sign` | Not run to completion — environment blocker (exit 64) | Signing stopped before build because no signing identity was provided. Linux also has no `codesign`. |
| `scripts/release_validation.sh --signed-app artifacts/release/PulseFiles.app` | Not run to completion — environment blocker (nonzero) | `swift test` stopped at `import AppKit` with `no such module 'AppKit'`; the signed-app harness was therefore never reached. |

Swift was `6.1.3` targeting `x86_64-unknown-linux-gnu`. The requested signed app
does not exist. These outcomes are not product failures and are not pass evidence.

## Checklist scenario evidence

| Checklist scenario | Result | Reason / required follow-up |
| --- | --- | --- |
| 1. First launch / clean installation | **Not run — blocker** | Requires a signed app and clean macOS account. |
| 2. Dual-pane navigation | **Not run — blocker** | AppKit application cannot launch on this host. |
| 3. Parent row and Command-Up | **Not run — blocker** | Requires macOS UI; restricted checks also need the DEBUG sandbox. |
| 4. Search/filter | **Not run — blocker** | Requires macOS UI. |
| 5. Hidden-file toggle | **Not run — blocker** | Requires macOS UI and relaunch. |
| 6. Copy, move, rename, Trash, permanent delete | **Not run — blocker** | Requires disposable OS-level isolation; none was available. |
| 7. Conflict handling and replacement recovery | **Not run — blocker** | Replacement safety is V1-blocking and must be exercised with disposable data on macOS. |
| 8. Operation cancellation | **Not run — blocker** | Cancellation, cleanup, integrity, and partial-failure reporting require macOS fixtures. |
| 9. Sidebar shortcuts and recents | **Not run — blocker** | Requires system folders and signed-app relaunch. |
| 10. Security-scoped folder grants | **Not run — blocker** | Requires signed app; grant persistence across relaunch is unverified. |
| 11. Restricted DEBUG sandbox mode | **Not run — blocker** | Requires a macOS DEBUG app and disposable sandbox fixture. |
| 12. Release unrestricted mode | **Not run — blocker** | Requires signed release app. |
| 13. Experimental Terminal containment | **Not run — blocker** | Requires macOS app and disposable isolated data. |
| 14. Settings persistence after relaunch / prior-schema upgrade | **Not run — blocker** | Requires signed-app clean and prior-schema test accounts. |
| 15. Mounted-volume changes | **Not run — blocker** | Requires a disposable macOS disk image or external volume. |
| 16. Storage compatibility matrix | **Not run — blocker** | iCloud, network share, removable/read-only media, packages, symlinks, Finder aliases, and metadata all remain unverified. |

TCC-denied locations and Finder/Open With behavior are likewise unverified
because they depend on macOS TCC and Launch Services.

## Signed-app-only scenario evidence

| Checklist scenario | Pass/fail | Evidence | Tester/date | Notes |
| --- | --- | --- | --- | --- |
| 10. Security-scoped folder grants | Not run — blocker | This record | Codex / 2026-07-26 | Signed app and macOS unavailable. |
| 12. Release unrestricted mode | Not run — blocker | This record | Codex / 2026-07-26 | Signed app and macOS unavailable. |
| 14. Settings persistence after relaunch | Not run — blocker | This record | Codex / 2026-07-26 | Clean and upgrade accounts unavailable. |
| 15. Mounted-volume changes | Not run — blocker | This record | Codex / 2026-07-26 | Disposable macOS volume unavailable. |
| 16. Cloud folder | Not run — blocker | This record | Codex / 2026-07-26 | iCloud unavailable. |
| 16. Network share | Not run — blocker | This record | Codex / 2026-07-26 | macOS network mount unavailable. |
| 16. Removable/read-only media | Not run — blocker | This record | Codex / 2026-07-26 | Required media/isolation unavailable. |
| 16. Package | Not run — blocker | This record | Codex / 2026-07-26 | Signed-app behavior unavailable. |
| 16. Symbolic link | Not run — blocker | This record | Codex / 2026-07-26 | Signed-app behavior unavailable. |
| 16. Finder alias | Not run — blocker | This record | Codex / 2026-07-26 | Finder unavailable. |
| 16. Metadata | Not run — blocker | This record | Codex / 2026-07-26 | macOS metadata/provider behavior unavailable. |

## UI harness artifact evidence

| Harness workflow set | Pass/fail | Artifact directory | Tester/date | Notes |
| --- | --- | --- | --- | --- |
| All required signed-app workflows | Not run — blocker | None | Codex / 2026-07-26 | Validation stopped during compilation; no signed app, AppKit, System Events, or Accessibility authorization. |

## Release gate summary

| Release gate | Outcome | Evidence | Owner/date | Notes |
| --- | --- | --- | --- | --- |
| Commit SHA matches signed app | Not run | This record | Codex / 2026-07-26 | No signed app. |
| Version/build match `release/VERSION` | Pass (source metadata only) | `release/VERSION` | Codex / 2026-07-26 | Does not validate a bundle. |
| macOS versions tested | Not run — blocker | This record | Codex / 2026-07-26 | Linux host only. |
| Signed-app UI harness | Not run — blocker | This record | Codex / 2026-07-26 | Harness never reached. |
| Storage-provider matrix | Not run — blocker | This record | Codex / 2026-07-26 | No provider scenario verified. |

## Known limitations, failures, and documented limitations

| ID | Scenario/target | Status | Impact and reproduction | Evidence | Owner | Target release | Approval | Customer-facing text |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QA-ENV-001 | Entire signed macOS matrix | **Blocker** | Attempt either recorded command on this Linux host; signing/AppKit are unavailable. Run the full checklist on the required signed macOS matrix. | This record | Release manager (unassigned) | 1.0.0 | Not approved | The current candidate has not completed signed-macOS release verification. |

No observed data-integrity, sandbox-enforcement, replacement-safety, or
partial-failure-reporting failure is being downgraded to a limitation. Those
areas were not exercised and remain V1 blockers until they pass.

## Rollback plan

| Required field | Value |
| --- | --- |
| Rollback decision owner | Unassigned — must be completed by release manager |
| Rollback owner/contact | Unassigned — must be completed by release manager |
| Previous known-good version/build/SHA | Not supplied |
| Distribution rollback steps and communication link | Not supplied |

## Sign-off

- [ ] Evidence includes a pass/fail result for every signed-app-only scenario.
- [ ] Target matrix includes passing macOS 13, 14, 15, and current-release runs.
- [ ] Coverage includes a clean account, prior-schema upgrade, Apple Silicon, and Intel.
- [x] Unverified signed-app behavior is explicitly blocking rather than marked passed.

**Release decision: BLOCKED — do not ship this candidate based on this record.**

Release manager: _Not signed_  Date: 2026-07-26
