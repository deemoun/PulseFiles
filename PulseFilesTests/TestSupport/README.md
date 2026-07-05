# Test Support Conventions

`POM/` contains lightweight Page Object / Screen Object helpers for PulseFiles tests.
These robots intentionally do **not** drive AppKit UI automation yet. Instead, they
wrap view models, services, isolated `UserDefaults`, temporary directories, and fake
collaborators so tests can describe user flows with the same names future UI tests
should use (`app.leftPane.navigate(...)`, `app.commandBar.expectAction(...)`, etc.).

## Current strategy: pure SwiftPM logic-backed robots

PulseFiles currently stays with a pure SwiftPM test setup. That means the POM-style
helpers live in the `PulseFilesTests` unit test target and are backed by testable app
logic rather than by `XCUIApplication` / `XCUIElement`. This keeps the package simple
while still making higher-level tests read like user workflows.

Use the existing robot names as the stable vocabulary for user-facing surfaces:

- `AppRobot` coordinates the dual-pane shell and active-pane state.
- `FilePaneRobot` covers pane navigation, sorting, filtering, and selection.
- `CommandBarRobot` covers command-bar action-to-command behavior.
- `SidebarRobot` covers bookmark and recent-location behavior.
- `TerminalRobot` covers the experimental terminal settings contract.

Keep robots dependency-injected and sandbox-safe: fixtures should live in temporary
test directories, fake file-system collaborators are preferred for navigation and
listing expectations, and destructive filesystem behavior should stay in existing
service-level tests.

## Protocol-first rule for future UI backing

UI-facing test abstractions should remain protocol-based. Protocols let the current
logic-backed robots and future UI-backed page objects share the same behavioral
contract without forcing production code or unit tests to import XCTest UI types.
When adding a new robot/page-object capability:

1. Add the capability to a narrow protocol in `PulseFilesTests/TestSupport/POM/`.
2. Implement it on the logic-backed robot using view models, services, or fakes.
3. Keep method names user-centered (`navigate`, `filter`, `expectVisibleItemNames`)
   rather than implementation-centered (`clickTableRow`, `readNSTableViewCell`).
4. Avoid exposing AppKit internals in the shared protocol; UI automation can map the
   same method names to accessibility identifiers later.

## Later strategy: Xcode UI test bundle

Do **not** add a full UI test target until the build setup can launch the
SwiftPM-built `.app` reliably in automation. When the project is ready to adopt one,
create a separate target such as `PulseFilesUITests` and keep the POM names aligned
with this directory.

Recommended future UI-backed wrappers:

- `PulseFilesApplication`, backed by `XCUIApplication`, for app launch, global menu
  and window-level expectations, and top-level access to page objects.
- `FilePanePage`, backed by pane-scoped `XCUIElement` queries, mirroring
  `FilePaneRobot` names for navigation, filtering, sorting, selection, and
  expectations.
- `CommandBarPage`, backed by command-bar controls and menu/keyboard entry points,
  mirroring `CommandBarRobot` command vocabulary.
- `SidebarPage`, backed by sidebar `XCUIElement` queries for bookmarks and recent
  locations.

The future UI target should reuse the naming and behavior contracts from
`PulseFilesTests/TestSupport/POM/` rather than inventing a separate testing language.
Logic-backed robots can continue to cover fast deterministic flows, while UI-backed
pages should focus on launch, accessibility wiring, AppKit integration, keyboard
shortcuts, and end-to-end smoke coverage.
