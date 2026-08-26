# Contributing to PulseFiles

Thank you for helping improve PulseFiles. This project welcomes focused bug
reports, proposals, documentation, tests, and code changes.

## Report an issue or propose a change

- Search [existing issues](https://github.com/deemoun/PulseFiles/issues) before
  opening a new one.
- Use the [issue chooser](https://github.com/deemoun/PulseFiles/issues/new/choose)
  for a reproducible bug report or a focused feature proposal. Include the
  macOS and PulseFiles versions, steps, expected and actual behavior, and logs
  or screenshots that do not expose private file names or contents.
- Discuss substantial features, architectural changes, and behavior that may
  affect data safety in an issue before investing in an implementation.
- Keep support and security-sensitive details out of unrelated issues. Do not
  upload private filesystem data.

## Set up a development environment

Development requires macOS 13 or later, Swift 5.9 or later, Git, and Xcode or
compatible Apple command-line developer tools. Clone the repository, then run:

```sh
git clone https://github.com/deemoun/PulseFiles.git
cd PulseFiles
swift test
./scripts/build_app.sh
open artifacts/PulseFiles.app
```

PulseFiles is an AppKit application managed by Swift Package Manager. Do not
commit generated `.build/` or `artifacts/` content. `AGENTS.md` provides
optional, detailed implementation guidance for contributors and coding agents;
this document is the primary human contribution guide.

## Make and verify a change

Keep models, services, controllers and views, commands, and utilities separated.
Start with the narrowest check that covers the change, then expand coverage when
the change crosses layers or affects the runnable app:

| Change | Narrow verification |
| --- | --- |
| Architecture or filesystem boundaries | `./scripts/validate_architecture.sh` |
| Core models and utilities | `swift test --filter PulseFilesCoreTests` |
| Filesystem, access, or persistence services | `swift test --filter PulseFilesServicesTests` |
| Application or cross-layer behavior | `swift test --filter PulseFilesTests` |
| AppKit wiring or accessibility | `swift test --filter PulseFilesAppKitUITests` |
| Full package | `swift test` |
| Disposable automation | `./scripts/run_automation_tests.sh` |
| Automation without Accessibility permission | `./scripts/run_automation_tests.sh --skip-system-events` |
| Local DEBUG app bundle | `./scripts/build_app.sh` |

Add focused XCTest coverage for new behavior and regressions. Put tests in the
target matching the layer under test, prefer temporary disposable directories
for filesystem tests, and cover failure, cancellation, and conflict paths where
relevant. UI changes should preserve keyboard behavior and include accessible
names, labels, tooltips, identifiers, or AppKit UI coverage as appropriate.

## Protect users' files

- Perform every filesystem mutation through `FileOperationService`; UI code
  must never mutate the filesystem directly.
- Route every external or user-provided URL through `SandboxFileAccessPolicy`
  before browsing or mutation.
- Preserve preflight validation, explicit replace/skip/cancel conflict handling,
  cancellation, progress, and partial-result reporting. Never overwrite silently.
- Test destructive behavior only with backed-up, disposable fixtures.
- Keep the experimental terminal opt-in, disabled and hidden by default, and
  preserve its first-use warning. Do not weaken DEBUG sandbox restrictions.

## Open a pull request

Create a small, focused branch and pull request with a clear title. Explain the
problem and user-visible result, identify filesystem/sandbox/terminal safety
effects, list the exact verification commands and results, and call out skipped
checks or environmental limitations. Link the relevant issue, add documentation
and localized strings when behavior changes, and avoid unrelated reformatting.

## Contribution license

PulseFiles accepts contributions under **GPL-3.0-or-later** using an
**inbound-equals-outbound** policy: by submitting a contribution, you agree that
it may be distributed under the project's GPL-3.0-or-later license. You retain
copyright in your contribution. No Developer Certificate of Origin (`Signed-off-by`)
and no separate contributor license agreement are required.

Only submit work you have the right to contribute. Identify any incorporated
third-party material and its license so maintainers can confirm compatibility
with the project license. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
