# PulseFiles AppKit UI harness

`PulseFilesAppKitUITests` is the deterministic UI suite for the SwiftPM
package. SwiftPM cannot create or run an Xcode `XCUIApplication` test bundle,
so the suite launches the production `MainWindowController` in an AppKit
application and drives it through the stable identifiers in
`PulseFiles/Utilities/AccessibilityIdentifiers.swift`.

Run it on macOS with:

```sh
swift test --filter PulseFilesAppKitUITests
```

The suite intentionally complements rather than replaces `PulseFilesTests`:
service-level conflict resolution, destructive-operation safety, drag/drop
policy, recents persistence, and terminal warning acknowledgement stay in the
existing deterministic unit tests. The AppKit suite verifies that their
controller entry points and visible accessibility anchors remain wired.
