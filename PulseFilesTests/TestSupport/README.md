# Test Support Conventions

`POM/` contains lightweight Page Object / Screen Object helpers for PulseFiles tests.
These robots intentionally do **not** drive AppKit UI automation yet. Instead, they
wrap view models, services, isolated `UserDefaults`, temporary directories, and fake
collaborators so tests can describe user flows with the same names future UI tests
should use (`app.leftPane.navigate(...)`, `app.commandBar.expectAction(...)`, etc.).

Keep robots dependency-injected and sandbox-safe: fixtures should live in temporary
test directories, fake file-system collaborators are preferred for navigation and
listing expectations, and destructive filesystem behavior should stay in existing
service-level tests.
