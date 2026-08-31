# PulseFiles Architecture and Maintenance Guide

This document is the engineering reference for future maintainers and coding
agents. It complements README.md, which is the concise product overview.
PulseFiles is a macOS 13+ AppKit file manager built as a Swift Package Manager
executable. It is intentionally a native, keyboard-first, dual-pane application;
do not introduce a SwiftUI rewrite without an explicit product decision.

## Dependency policy

Production code is separated into SwiftPM modules that enforce the allowed
direction at compile time:

```text
PulseFilesUtilities → PulseFilesModels → PulseFilesServices
    → PulseFilesWorkflows → PulseFiles (AppKit presentation and composition)
```

Arrows mean “may be depended on by.” `PulseFilesUtilities` contains
Foundation-only, model-independent helpers. `PulseFilesModels` contains shared
value and state types and may depend on utilities. Utilities must not import
models, services, or presentation; models must not import services or AppKit.
`PulseFilesServices` owns filesystem access, mutation, policy, and Foundation
persistence implementations. `PulseFilesWorkflows` owns reusable commands and
routing decisions. AppKit adapters and composition may depend on every lower
layer. Reverse dependencies are forbidden and checked by
`scripts/validate_architecture.sh`.

Cross-target declarations use Swift's `package` access level so they remain
implementation details rather than public library API. The executable re-exports
its package-internal layers only to keep presentation files concise; each lower target declares its own imports and dependencies.

### Presentation dependency graph

`PulseFilesApp` is the composition layer (the executable target is currently
named `PulseFiles`). It is the only presentation node that may select concrete
filesystem, access-policy, persistence, or process implementations. Presentation
features are independently testable AppKit modules and are peers, never a stack:

```text
PulseFilesApp (composition root)
  ├── PulseFilesPane ───────────────┐
  ├── PulseFilesSidebar ────────────┤
  ├── PulseFilesSettings ───────────┼──→ PulseFilesPresentationSupport
  └── PulseFilesTerminal ───────────┘

PulseFilesApp ───────────────→ PulseFilesWorkflows → PulseFilesServices
feature modules ─────────────→ minimum required Models / Services protocols
PulseFilesPresentationSupport → PulseFilesServices / Models / Utilities
PulseFilesServices ──────────→ PulseFilesModels → PulseFilesUtilities
```

An arrow means “may depend on.” There are no arrows between pane, sidebar,
settings, and terminal. A feature reports intent through a model value, closure,
delegate, or small capability protocol; `PulseFilesApp` coordinates the receiving
feature and injects implementations. In particular, features do not construct
`FileSystemService`, `FileOperationService`, `SandboxFileAccessPolicy`, concrete
persistence services, or `PTYTerminalProcess`.

`PulseFilesPane`, `PulseFilesSidebar`, `PulseFilesSettings`, and
`PulseFilesTerminal` are separate peer targets. Shared AppKit-facing values and
capability protocols live in `PulseFilesPresentationSupport`; AppKit-free values
live in `PulseFilesModels`. `PulseFiles/Debug` deliberately remains an
application-only DEBUG adapter rather than a target: its single log controller is
created only by the composition root, has no reusable feature boundary, and a
standalone module would add an artificial peer without an independently testable
API. If Debug grows reusable state or capability contracts, extract those lower
first and reassess the target boundary. `scripts/validate_architecture.sh` enforces the graph from the machine-readable
`scripts/architecture_policy.json`. To add or move a production module, register
its exact SwiftPM target name, source path, and complete list of direct internal
dependencies in `productionTargets`, then make the matching `Package.swift`
declaration. The validator assigns every Swift source to the most-specific
registered path and checks all `PulseFiles*` imports, including imports owned by
the executable composition target. Test targets are registered the same way in
`testTargets`, so every declared target path and direct internal dependency is
checked rather than only the production feature modules.

Peer presentation targets may construct types declared in their own source tree,
but service-layer resource owners are discovered from declarations and are denied
by default. An unavoidable construction exception must be added to
`serviceConstructorExceptions` as an exact `relative/path/File.swift:TypeName`
entry, with a rationale beside the owning code and in review. Direct filesystem
mutation exceptions likewise use exact paths in `presentationMutationExceptions`;
wildcards and directory exceptions are not permitted.

Declarations crossing targets use `package`, not `public`. Target manifests must
list only directly imported lower layers. Production factories, singleton
selection, and adapters that join multiple features remain under `PulseFiles/App`.

Filesystem mutation lives in `PulseFilesServices`. Its concrete validators,
planners, executors, schedulers, metadata preservation, staging, and copy
implementations remain package-internal. Operation request/result values live in
`PulseFilesModels`; presentation and workflows cross the service boundary through
the minimum caller-facing capability protocols.

Concrete services and process-wide singletons are selected only at the application
composition root. In production, `AppDelegate` (through
`makeProductionMainWindowController`) assembles the complete per-window object graph;
`MainWindowController` and nested presentation controllers only consume injected
instances. In particular, every pane, sidebar, terminal, and workflow in a window
must share that graph's single `SandboxFileAccessPolicy` and folder-grant service.
Controllers and
workflow coordinators receive only the narrow capabilities they use through
`MainWindowDependencies`, `MainWindowWorkflowDependencies`, and their initializers.
Controllers must not hide fallback production-service construction in stored
properties or default arguments. This makes resource ownership explicit and allows
asynchronous behavior to be tested without filesystem or operating-system access.

Add a small protocol only where substitutability provides concrete testing or
ownership value. Examples include thumbnail loading, terminal enablement/state,
file-size resolution, diagnostics export, standard-folder access, and viewer
content loading. Keep passive value models concrete; data without behavior or an
independently owned resource does not need a protocol.

## Runtime architecture

PulseFilesApplication starts AppKit. AppDelegate builds menus and the app icon,
creates MainWindowController, and terminates the app after the final window closes.
MainWindowController owns one MainWindowViewController.

AppDelegate is the sole production composition root for injectable filesystem and
macOS integration dependencies. `AppDelegate.makeProductionMainWindowController`
is the only production object-graph assembly point. MainWindowViewController creates the left and
right FilePaneViewControllers, owns toolbar search and active-pane state, and keeps
the cross-pane composition boundary. Focused workflow coordinators under `App/Coordinators` own file transfer and
clipboard flow, creation naming, descendant search, auxiliary windows, and the
mechanics of installing sidebar/terminal child views. Preview availability,
volume-loss navigation decisions, operation result/undo state, and value-only
window layout state remain separately testable. Menus, toolbar,
command bar, context menus, and global keyboard actions should converge on its
performCommand path. Keep cross-pane behavior here, not in a pane controller.

| Directory | Content |
| --- | --- |
| PulseFiles/App | Lifecycle, menus, window and high-level UI coordination. |
| PulseFiles/FilePane | Pane view model/controller, file table, breadcrumbs, rows and status views. |
| PulseFiles/Sidebar | Locations, mounted devices/recent folders and selection inspector. |
| PulseFiles/Terminal | Experimental Terminal interface and process adapter; opt-in and disabled by default. |
| PulseFiles/Settings | Preferences UI. |
| PulseFiles/Commands | AppKit-independent commands and workflow routing. |
| PulseFiles/Models | Small value models. |
| PulseFiles/Services | Filesystem, operations, policy, persistence, monitoring and diagnostics. |
| PulseFiles/Utilities | Foundation-only formatting, validation, flags, localization, and path helpers. |
| PulseFiles/PresentationSupport | AppKit-only icons, colors, shortcuts, pasteboard/macOS adapters, and presentation models split from lower layers. |
| PulseFilesCoreTests | AppKit-free tests for utilities and value models. |
| PulseFilesServicesTests | Service tests for filesystem behavior, access policy, and persistence. |
| PulseFilesTests | Application and integration tests for cross-layer workflows and composed behavior. |
| PulseFilesAppKitUITests | In-process AppKit wiring and accessibility tests. |

## Pane browsing lifecycle

Each pane composes two focused state owners. The AppKit-free
`PaneNavigationStateMachine` owns `PaneState` (tabs, current directory, marks,
focus, history, sorting, and hidden-file preference) and performs tab activation,
history commit/rollback, and restoration. The main-actor
`DirectoryLoadCoordinator` owns the snapshot cache and directory monitor plus the
complete asynchronous load lifetime. `FilePaneViewModel` remains the package-facing
main-actor facade: it composes those owners, applies search filtering, persists
display preferences, and publishes the existing pane callbacks.

Loads move through one explicit coordinator state (`idle`, `loading`, `loaded`,
`failed`, or `retryScheduled`). Each request advances a generation; watchdogs,
partial-refresh retries, monitor notifications, and filesystem completions are
accepted only for the current generation, so cancellation-resistant stale work
cannot replace newer navigation or tab state. Cache and monitor dependencies are
injected, making teardown deterministic. Access policy validation still wraps
every enumeration and metadata read, while failures retain prior directory/items
and history transitions roll back. On a mount change the pane refreshes or falls
back to a policy-valid directory if its current path vanished.

FilePaneViewController owns exactly one pane and its FilePaneViewModel. It retains
the pane state machines: URL-backed selection, focused-item identity, navigation
callbacks, and view-model binding. Focused collaborators adapt AppKit around that
owner: FilePaneTableAdapter renders rows and lays out columns;
FilePaneDropCoordinator extracts pasteboard URLs, resolves destinations and applies
DropTransferPolicy without mutating the filesystem; InlineRenameCoordinator owns
the field editor lifecycle and reload/commit policies; and
FilePaneContextMenuProvider constructs context and Open With menus that emit
MainCommand values through the controller callback. Narrow GalleryImageView,
InlineRenameTextField, and PaneContainerView files contain their view-only behavior.
All mutation intent, including accepted drops, is sent upward through controller
callbacks rather than invoking filesystem services. The
synthetic parent row (..) appears only without an active search filter. Parent,
breadcrumb and go-to navigation must remain policy validated so restricted mode
cannot be escaped through UI affordances. The active pane receives toolbar search;
Tab switches panes. Single-pane mode hides, but does not discard, the other
pane's location.

FileSystemService validates access, enumerates resource values, creates FileItem
records, then sorts them. Sorting is always folder-first, including descending
sorts. Name uses localized standard comparison; kind, size and modified date use
deterministic name tie-breakers. Directory sizes intentionally remain zero:
browsing must not recursively size a tree. FileItem contains the URL, display/type
metadata, visibility, ownership/permissions, dates, classification and native icon.

## Commands and keyboard behavior

MainCommand is the canonical action enum. MainCommandRouter uses both-pane state,
operation state, access eligibility and undo availability to return an active-pane
route, cross-pane route, pane switch, enabled action, or explicit disabled reason.
Use it instead of duplicating selection checks.

Copy and Move use selected URLs in the active pane and the inactive pane directory.
FileClipboard stores URL objects plus a PulseFiles copy/move marker in the system
pasteboard. Drag/drop resolves to the same eventual operation path. CommandBarAction
maps command-bar buttons; KeyboardShortcutManager contains narrow shortcut logic.

Primary shortcuts: Tab switches pane; Return opens; Backspace or Command-Up goes to
parent; Command-[ and Command-] use history; Command-Shift-G goes to a folder;
Command-N and Command-Shift-N create a folder/file; Command-C/X/V use clipboard;
Command-Shift-. toggles hidden files; Command-backtick toggles terminal after
opt-in; Command-. cancels an operation. Function-key equivalents are in the command
bar. Do not consume ordinary typing keys while a text input is focused.

When adding a command, update the action enum, router tests/rules, menus and
validation, toolbar, command bar, pane key handling, main-window execution,
localization and accessibility labels as applicable.

## Filesystem access and safety

### Access policy

SandboxFileAccessPolicy is the only authorization gate. Validate every browse URL,
external URL, drop, source and destination through it, even in release builds, so
macOS permissions and granted folders are consistently handled. Never bypass it
just to make a feature work.

Release builds have normal file-manager behavior subject to macOS permissions.
DEBUG is also unrestricted by default, but may enable experimental restriction with
--pulsefiles-enable-experimental-sandbox or its UserDefaults flag;
--pulsefiles-disable-experimental-sandbox forces it off. When enabled, the root is:

    ~/Library/Application Support/PulseFiles/ExperimentalSandbox

Outside the root, explicit folder access is required. FolderAccessGrantService
persists and resolves security-scoped bookmark grants through
FolderAccessBookmarkResolving. Use policy scoped access for an operation and its
validated-directory fallback for navigation.

### Mutations

Only FileOperationService may create, rename, copy, move, trash or permanently
delete user files. It preflights empty/duplicate/missing sources, destination
existence/writability, policy access, descendant/self destinations and conflicts.
Conflicts require replace, skip or cancel; never overwrite silently. Transfers can
stream content, report FileOperationProgress, respond to cancellation, and return
FileOperationResult with successes, skips, failures, cleanup warnings and
cancellation. The main window retains FileOperationRecovery only for recoverable
rename/move results.

Limits that must remain visible in code and UI:

* Finder aliases are detected but unsupported for mutation; leave them unchanged.
* Symbolic links are copied as links rather than traversing their targets.
* Packages are copied/moved as directory trees; generic operations cannot promise
  application-specific package integrity.
* Cloud items, providers, network shares, removable disks and permissions can
  change after preflight; preserve partial-failure reporting and recovery advice.
* Permissions, ownership where permitted, timestamps, tags/labels, xattrs and ACLs
  are best-effort metadata. Content can succeed while metadata emits a warning.

## Services and models reference

| Type(s) | Responsibility |
| --- | --- |
| FileItem, FileItemType | Immutable presentation-ready directory entry and classification. |
| PaneID, PaneState, FileSortDescriptor, FileSortKey | Per-pane identity, state and sorting. |
| NavigationHistory | Back/forward stacks; a new visit clears forward history. |
| Bookmark | Codable user favorite record. |
| FileOperation, FileOperationKind, FileOperationRecovery | Requested mutation and move/rename reversal data. |
| VolumeStatusPresentation | Lightweight volume capacity/read-only/availability status; never walks a directory. |
| FileSystemService / FileSystemServicing | Async validated enumeration and sorting; retain protocol injection for tests. |
| SandboxFileAccessPolicy | Authorization for source, directory and destination access. |
| FolderAccessGrantService | Security-scoped folder grant persistence and access scopes. |
| FileOperationService / FileOperationServicing | Only mutation service; use injectable file-manager/copier collaborators in tests. |
| FileHandleStreamingCopier | Production streaming copier with progress/cancellation. |
| FileClipboard | Pasteboard URLs and copy/cut marker. |
| DirectoryMonitor | Watches a folder and asks the view model to reload. |
| BookmarkService / RecentLocationService | Persist favorites and bounded, de-duplicated recents. |
| SettingsSnapshot / SettingsRepository | AppKit-free value snapshot plus the sole owner of v1 UserDefaults keys, JSON migration, and atomic import/export. |
| StartupNavigationService | Resolves saved/startup directories, folder grants, access-policy validation, and safe fallbacks. |
| SettingsService / WindowSessionState | Narrow presentation adapter (including RGBA/NSColor conversion) and per-window, non-persistent UI state. |
| TerminalService | Computes Experimental Terminal visibility/warning state; never enables it by default. |
| VolumeDiscoveryService / VolumeChangeMonitor | Mounted-volume snapshots and Workspace mount/unmount updates on main actor. |
| DiagnosticLogService / DiagnosticLogger | Bounded in-memory log; sanitizes paths, redacts common secrets and truncates messages. |

## UI reference

| Type | Responsibility |
| --- | --- |
| MainWindowViewController | Child-controller ownership, active-pane state, split composition, and routing typed coordinator outputs to pane and feature events. |
| MainWindowCommandCoordinator / MainCommandRouter | The coordinator assembles transient pane/operation/access validation state and emits typed routes; the AppKit-independent router remains the sole decision engine. |
| FileOperationPresentationCoordinator | Builds confirmations, conflict choices, operation-result alerts, and diagnostics-export presentation without acquiring a filesystem mutation capability. |
| MainWindowDependencies | Injectable filesystem operations/probing/search, recents, bookmarks, volumes, clipboard, and application opening boundaries. |
| MainWindowWorkflowDependencies | Injected archive/rename, file-transfer, creation, descendant-search, Open With, Go to Folder, and auxiliary-panel workflow collaborators. |
| FileTransferWorkflowCoordinator | Owns clipboard sessions plus paste/drop validation and copy/move orchestration; the controller supplies only source and destination pane context. |
| FileCreationWorkflowCoordinator / ArchiveAndRenameWorkflowCoordinator | Own creation/archive/batch-rename prompting, request submission, unique-name suggestions, and result callbacks. |
| SearchWorkflowCoordinator / OpenWithWorkflowCoordinator / GoToFolderWorkflowCoordinator | Protocol-backed AppKit prompting, cancellable descendant search and result routing, application selection, and safe asynchronous path resolution. |
| AuxiliaryPanelCoordinator | Settings/debug-log window lifetime and sizing. |
| SidebarLayoutCoordinator / TerminalLayoutCoordinator | Authoritative child-view installation/removal and persisted split sizing/session lifecycle; the window composes their typed visibility outputs. |
| FileOperationCoordinator / MainCommandRouter | Operation generation, detached-task/cancellation state, progress/result presentation state and undo recovery; authoritative command availability and typed cross-pane targets. |
| PreviewCoordinator / NavigationCoordinator / WindowLayoutController | Preview probing, standard/volume-loss navigation decisions, and value-only split/sidebar/terminal state. |
| FilePaneViewModel | Per-pane async loading, history, filtering, sorting, hidden files and safe navigation. |
| FilePaneViewController | Table/breadcrumb/status rendering, selection and drag/drop adaptation. |
| FileTableView | Converts native table events to delegate requests; owns no operation policy. |
| PaneKeyboardNavigationController | Maps unmodified pane arrows to focus or horizontal navigation requests. Modified arrows remain in the command/AppKit responder chain; text editors therefore retain normal cursor movement. Horizontal arrows are consumed when their destination is unavailable, making Right Arrow on a file and Left Arrow at a root or access-policy boundary safe no-ops. |
| BreadcrumbView | Clickable path components. |
| PaneStatusView / PaneContentOverlayView | Selection/volume information and loading/error recovery UI. |
| SidebarViewController | Locations/devices/recents and asynchronous selection inspection. |
| TerminalViewController | Opt-in shell input/output, process lifecycle and working-directory access scope. |
| SettingsViewController / SettingsPageController | Category host and stable page registry. Focused General, Appearance, Navigation, Access, and Experimental page controllers own their controls, reload through typed `SettingsService` properties, and report changes to the host; folder selection, access grants, and cleanup services are injected only into pages that use them. |
| DebugLogViewController | Filterable diagnostic-log view. |
| CommandBarView | Bottom action bar, modifier-aware labels and operation progress/status. |

### Main-window incremental responsibility inventory

The large window controller is being reduced section by section rather than
rewritten. The distinctive method groups now have these ownership boundaries:

* `performCommand`: `MainWindowCommandCoordinator` captures the validation
  snapshot and emits a `MainCommandRoute`; `MainCommandRouter` alone decides
  availability and targets. The controller only updates active-pane ownership
  and translates the typed route into a feature event.
* `promptForNewFolder`: creation, archive/rename, search, Open With, scratch, and
  auxiliary-window coordinators own prompt/workflow rules. The controller supplies
  the current pane/directory and handles typed success or cancellation outputs.
* `performFileTransfer` and `startFileOperation`: workflow coordinators validate
  requests and `MainWindowFileOperationCoordinator` owns operation lifecycle.
  Mutations continue exclusively through injected `FileOperationCoordinating`.
* Operation alerts, conflict prompts, result models, and diagnostics export
  presentation belong to `FileOperationPresentationCoordinator`; it receives no
  pane, sidebar, settings, or terminal module dependency.
* `toggleTerminal` and `setSidebarVisible`: `TerminalLayoutCoordinator` and
  `SidebarLayoutCoordinator` are the installation/session/split-size authorities.
  The controller composes their views and routes focus or persisted-setting events.
* `applySettingsChanges`: the controller broadcasts typed setting changes to the
  owned children and layout coordinators; it does not recreate production services.

Coordinator inputs and outputs are deliberately small closures over values or
typed routes. Cross-feature adapters stay in the application composition target,
and production construction remains confined to
`AppDelegate.makeProductionMainWindowController`.

Key utilities: ExperimentalFlags (sandbox switches), FileNameValidator (create/rename
input), FilePathComparison and PathUtilities (path safety), FileSizeFormatter and
date formatting, FileTypeColorPalette, NSImage file icons, Localization,
LiquidGlassStyle and AccessibilityIdentifiers. Keep these focused; do not turn one
into a general utility dumping ground.

## Sidebar, terminal, settings and diagnostics

The sidebar supplies navigation locations, favorites, recents and mounted devices.
VolumeDiscoveryService reads mounted-volume resource values; VolumeChangeMonitor
republishes after Workspace mount/unmount notifications. If a volume disappears,
panes refresh or fall back to an authorized directory. Expensive inspector details
such as aggregate size load asynchronously and must be tied to the active selection
identity so stale details do not appear.

The Experimental Terminal is an opt-in feature and is not a security boundary.
It is hidden and disabled by default, and users must first enable
SettingsService.experimentalTerminalEnabled. Its menu, toolbar, shortcut help, settings,
and panel use the Experimental Terminal label. First use warns that shell commands can
modify or delete files and may access any locations macOS has authorized for PulseFiles.
TerminalViewController follows an authorized active-pane directory where possible, holds
the access scope for command lifetime, reports launch/non-zero-exit errors, and can
best-effort stop a running process; it cannot undo shell changes.

SettingsRepository owns durable preferences and the compatible v1 JSON document;
StartupNavigationService owns launch-folder resolution and authorization. SettingsService
adapts those value types for focused settings-page interfaces, while WindowSessionState
owns manual terminal visibility for one window only. Apply changes to existing UI.
Favorites and recents belong to their services. Localized UI text uses
String.localized and Resources/en.lproj/Localizable.strings.

## Testing, builds and agent checklist

Run from the repository root:

    swift test
    ./scripts/build_app.sh
    ./scripts/build_app.sh --release
    ./scripts/release_validation.sh

`swift test` runs all four SwiftPM test targets: `PulseFilesCoreTests` provides
AppKit-free utility and model coverage; `PulseFilesServicesTests` exercises
filesystem, access-policy, and persistence services; `PulseFilesTests` covers
application and cross-layer integration behavior; and `PulseFilesAppKitUITests`
verifies in-process AppKit wiring and accessibility. For a focused development
iteration, use `swift test --filter PulseFilesCoreTests`, `swift test --filter
PulseFilesServicesTests`, `swift test --filter PulseFilesTests`, or `swift test
--filter PulseFilesAppKitUITests` as appropriate. A filtered run does not replace
the full `swift test` release gate.

Across those scopes, tests cover sorting, view-model navigation/cancellation,
routing, operations and partial failure, policy/grants, settings, terminal
behavior, volumes, diagnostics, and utilities. Use existing protocol injection,
fixtures and doubles; do not depend on a real user disk or defaults store. Build
scripts use .build and write bundles to artifacts; never commit either. For a
perceptible runnable UI change, build and capture a screenshot when launch is
possible.

Before finishing, confirm:

1. Every URL and mutation uses SandboxFileAccessPolicy.
2. Controllers do not directly mutate user files; use FileOperationService.
3. Main-actor UI and async race protections are maintained.
4. Commands are routed, validated, localized and consistently exposed.
5. Settings use SettingsService and apply to existing UI.
6. The Experimental Terminal remains opt-in, visibly labeled, and keeps its warning/access scope intact.
7. Provider/volume/metadata failures remain honest partial results.
8. swift test and the relevant build command have run; generated output is unstaged.

### File-operation façade and internal engine

`FileOperationService` is the sole filesystem-mutation façade used by UI and
workflow code. Public requests, progress values, results, and errors live in the
Models layer, while service capability protocols live under
`Services/FileOperations`. The façade always performs sandbox, source,
destination, writable-volume, duplicate-selection, descendant, and capacity
preflight before dispatching a mutation.

The internal engine is deliberately split by responsibility:
`FileOperationPreflightValidator` performs non-mutating safety checks;
`FileTransferPlanner` owns conflict decisions and keep-both naming;
`FileTransferExecutor` owns staged/recursive execution dependencies and
cancellation; `FileMetadataPreserver` owns timestamp, tag, extended-attribute,
and ACL preservation dependencies; and `DescriptorRelativeFileOperator`
performs descriptor-verified create, rename, remove, and symbolic-link calls.
These types are implementation details, not alternate mutation entry points.
Archive and batch-rename capabilities remain reachable through the same façade,
so partial results, recovery plans, staging cleanup warnings, and cancellation
semantics continue to be enforced at one boundary.
