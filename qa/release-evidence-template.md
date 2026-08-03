# PulseFiles Signed Release Evidence Template

Copy this template into the release record for every candidate signed `.app`.
Use one record per macOS version and architecture combination. Record evidence as
links, attached screenshots, console output, or an issue ID with enough detail
to reproduce the result. Do not mark a scenario as passed based only on `swift
run`, an unsigned app, or a DEBUG build.

## Release and environment

| Required field | Value |
| --- | --- |
| Release version | |
| Build number | |
| Build SHA (full commit SHA) | |
| Signed app path | |
| Signature authority chain (`codesign --display --verbose=4`, every `Authority=` line) | |
| Hardened runtime state (`flags` includes `runtime`) | |
| Apple notarization / Gatekeeper assessment result | |
| Staple verification result (`xcrun stapler validate`) | |
| Final distributable ZIP path | |
| Final ZIP SHA-256 digest and verification result | |
| Tester (name or team alias) | |
| Test date (UTC) | |
| macOS version and build number | |
| Hardware architecture (Apple Silicon or Intel) | |
| Test account | |
| Install path | |
| Install type (clean install or upgrade from prior version) | |
| Prior app version/build/SHA (required for upgrade) | |
| Upgrade result (required for upgrade: pass/fail plus retained settings, bookmarks, and recents result) | |
| Reset/fixture details and disposable test location | |
| Release notes/support/privacy/issue links reviewed | |

## Required coverage

Complete signed-app evidence across the following targets before release:

- macOS 13, macOS 14, macOS 15, and the current macOS release at release time.
  If the current release is one of 13–15, record it in that row and mark it as
  the current-release target rather than running it twice.
- At least one Apple Silicon run and at least one Intel run across the target
  matrix. Record the actual architecture in every evidence record.
- At least one run in a clean user account with no prior PulseFiles preferences
  or app support data.
- At least one upgrade run from the immediately prior released version. Record
  the prior version, install method, and whether settings, bookmarks, and
  recents migrated or failed safely.

| Target | macOS build | Architecture | Clean user account | Upgrade from prior release | Evidence record link | Status |
| --- | --- | --- | --- | --- | --- | --- |
| macOS 13 | | | | | | |
| macOS 14 | | | | | | |
| macOS 15 | | | | | | |
| Current macOS release (state version) | | | | | | |

## Signed-app-only scenario evidence

Record every scenario below on the signed release `.app`. The scenario numbers
match `RELEASE_CHECKLIST.md`. For a failure, use **Fail — blocker** unless the
documented-limitations record below has an approved owner and target release.

| Checklist scenario | Pass/fail | Evidence (link, screenshot, log, or issue) | Tester/date | Notes or reproduction summary |
| --- | --- | --- | --- | --- |
| 10. Security-scoped folder grants | | | | |
| 12. Release unrestricted mode | | | | |
| 14. Settings persistence after relaunch (final sign-off) | | | | |
| 15. Mounted-volume changes | | | | |
| 16. Version 1.0 storage compatibility — cloud folder | | | | |
| 16. Version 1.0 storage compatibility — network share | | | | |
| 16. Version 1.0 storage compatibility — removable media | | | | |
| 16. Version 1.0 storage compatibility — package | | | | |
| 16. Version 1.0 storage compatibility — symbolic link | | | | |
| 16. Version 1.0 storage compatibility — Finder alias | | | | |
| 16. Version 1.0 storage compatibility — metadata | | | | |

## UI harness artifact evidence

When Accessibility automation is available, run `scripts/release_validation.sh`
with `--security-evidence` and `--ui-artifacts-dir`. Attach the security report
(signature authorities, hardened-runtime state, notarization assessment, staple
validation, and final archive digest) and the resulting UI report,
before/after fixture tree snapshots, and screenshot. A missing Accessibility
permission is not evidence of a pass. Record the workflow set and artifact
location below.

| Harness workflow set | Pass/fail | Artifact directory or attachment | Tester/date | Notes |
| --- | --- | --- | --- | --- |
| navigation, active-pane search, non-mutating conflict choices, drag/drop, relaunch, terminal opt-in | | | | |

## Release gate summary

| Release gate | Outcome (pass/fail/not run) | Evidence link or artifact | Owner/date | Notes |
| --- | --- | --- | --- | --- |
| Commit SHA matches the signed app | | | | |
| Version and monotonically increasing build number match `release/VERSION` | | | | |
| Developer ID signature authority chain recorded | | | | |
| Hardened runtime enabled | | | | |
| Apple notarization accepted | | | | |
| Stapled ticket validated | | | | |
| Final ZIP SHA-256 digest verified and recorded | | | | |
| macOS versions tested | | | | |
| Signed-app UI harness | | | | |
| Storage-provider matrix (cloud, network, removable, package, symlink, alias, metadata) | | | | |

## Known limitations, failures, and documented limitations

An unresolved signed-app-only failure is a **release blocker**. It may be
released only as a documented limitation when product/release approval accepts
the limitation and every field below is completed. A limitation without a named
owner and target release remains a blocker.

| ID | Scenario/target | Status (blocker or documented limitation) | Impact and reproduction | Evidence/issue link | Owner | Target release | Approval | Customer-facing release-note text |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | |

## Rollback plan

| Required field | Value |
| --- | --- |
| Rollback decision owner | |
| Rollback owner/contact | |
| Previous known-good version/build/SHA | |
| Distribution rollback steps and communication link | |

## Sign-off

- [ ] Evidence includes a pass/fail result for every signed-app-only scenario.
- [ ] Security evidence records the signature authority chain, hardened-runtime
  flag, accepted notarization assessment, valid staple, and verified final ZIP digest.
- [ ] Target matrix includes macOS 13, 14, 15, and the current macOS release.
- [ ] Coverage includes at least one clean user account, one upgrade from the
  prior release, Apple Silicon, and Intel.
- [ ] Every unresolved failure is either blocking release or recorded above as
  an approved documented limitation with an owner and target release.

Release manager: ____________________  Date: ____________________
