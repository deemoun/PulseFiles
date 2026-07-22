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
| Signed app path, signing identity, and notarization/stapling status | |
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

## Failures and documented limitations

An unresolved signed-app-only failure is a **release blocker**. It may be
released only as a documented limitation when product/release approval accepts
the limitation and every field below is completed. A limitation without a named
owner and target release remains a blocker.

| ID | Scenario/target | Status (blocker or documented limitation) | Impact and reproduction | Evidence/issue link | Owner | Target release | Approval | Customer-facing release-note text |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | |

## Sign-off

- [ ] Evidence includes a pass/fail result for every signed-app-only scenario.
- [ ] Target matrix includes macOS 13, 14, 15, and the current macOS release.
- [ ] Coverage includes at least one clean user account, one upgrade from the
  prior release, Apple Silicon, and Intel.
- [ ] Every unresolved failure is either blocking release or recorded above as
  an approved documented limitation with an owner and target release.

Release manager: ____________________  Date: ____________________
