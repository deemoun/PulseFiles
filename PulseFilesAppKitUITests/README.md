# PulseFiles AppKit UI harness

`PulseFilesAppKitUITests` is the deterministic UI suite for the SwiftPM
package. SwiftPM cannot create or run an Xcode `XCUIApplication` test bundle,
so the suite launches the production `MainWindowController` in an AppKit
application and drives it through the stable identifiers in
`PulseFiles/Utilities/AccessibilityIdentifiers.swift`.

Run all automated tests (including this target on macOS) with:

```sh
./scripts/run_automation_tests.sh
```

The command creates per-run fixture and preferences directories, runs this
target only on macOS in a DEBUG sandbox-enabled configuration, and removes only
those directories afterward. For focused local AppKit work, `swift test --filter
PulseFilesAppKitUITests` remains available on macOS, but does not provide the
automation command's isolated configuration.

The suite intentionally complements rather than replaces the AppKit-free
`PulseFilesCoreTests`, service-focused `PulseFilesServicesTests`, and
application/integration `PulseFilesTests` targets. Service-level conflict
resolution, destructive-operation safety, drag/drop policy, recents persistence,
and terminal warning acknowledgement stay in the appropriate deterministic test
target. The AppKit suite verifies that controller entry points and visible
accessibility anchors remain wired. Its filtered command is a focused development
tool, not a replacement for the full `swift test` release gate.
