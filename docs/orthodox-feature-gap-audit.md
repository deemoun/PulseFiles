# Orthodox file-manager feature-gap audit

## Scope and status vocabulary

This audit treats **P0** as the minimum coherent, safe, keyboard-first orthodox
dual-pane experience for PulseFiles 1.x. It is an inventory, not a commitment to
copy another file manager exactly. The status labels mean:

- **Already implemented** — the behavior has a user-facing route and its required
  model/service support.
- **Partially implemented** — a useful slice exists, but the orthodox behavior
  described here is not complete.
- **Missing** — P0 requires the behavior and no usable implementation exists.
- **Deliberately deferred** — excluded from P0 by a product or safety decision;
  the absence is intentional rather than an unnoticed gap.

## P0 behavior audit

| P0 behavior | Status | Exact evidence and conclusion |
| --- | --- | --- |
| Two independently navigable panes with an active-pane focus model | **Already implemented** | `PaneID` and `PaneState` hold independent state; `FilePaneViewModel` owns each pane's loading/navigation state; two `FilePaneViewController` instances are coordinated by `MainWindowViewController`. `MainCommand.switchPane`, routed by `MainCommandRouter`, supplies Tab switching. |
| Single-pane/dual-pane layout toggle without discarding the hidden pane | **Already implemented** | `MainCommand.togglePaneLayout`, `MainCommandRouter`, and `MainWindowViewController` implement the toggle; `SettingsService.defaultSinglePaneMode` persists the default. The current shortcut is Command-T in `MainCommandShortcutRegistry`, but it is subject to the migration decision below. |
| Swap panes, synchronize the opposite pane, and reveal the focused item opposite | **Already implemented** | `MainCommand.swapPanes`, `.syncOppositePane`, and `.revealInOppositePane` are dual-pane routes in `MainCommandRouter` and are executed by `MainWindowViewController`. |
| Directory listing with native metadata, breadcrumbs, parent row, refresh, and filesystem change monitoring | **Already implemented** | `FileItem`, `FileSystemService`, `BreadcrumbView`, `FilePaneViewController`, `FilePaneViewModel`, and `DirectoryMonitor` provide the listing and refresh lifecycle. `MainCommand.parent` and `.refresh` route navigation and reload; `SandboxFileAccessPolicy` bounds all navigation. |
| Back/forward/parent navigation with per-pane history | **Already implemented** | Each `PaneState` owns a `NavigationHistory`; `FilePaneViewModel` updates it. `MainCommand.back`, `.forward`, and `.parent` are routed by `MainCommandRouter`. Navigation history is a **foundation to extend, not replace**, when tabs add a history per tab. |
| Direct location entry and standard locations | **Already implemented** | `MainCommand.goToFolder`, `.quickLocations`, `.home`, `.downloads`, `.applications`, and `.scratchDirectory` are executed by `MainWindowViewController`; `QuickLocation` models the picker and `StandardFolderAccessService` plus `SandboxFileAccessPolicy` validate access. |
| Persistent favorites/bookmarks and recent locations | **Already implemented** | `Bookmark` and `BookmarkService` provide add/remove/rename/reorder persistence; `RecentLocationService` persists bounded recents; `SidebarViewController` and `QuickLocation` expose both. Bookmark persistence is a **foundation to extend, not replace**. |
| Mounted-volume discovery and live mount/unmount updates | **Already implemented** | `Volume`, `VolumeDiscoveryService`, and `VolumeChangeMonitor` discover and monitor devices; `SidebarViewController` presents them, while `VolumeStatusPresentation` and `VolumeStatusResolutionCache` supply pane status. Volume discovery is a **foundation to extend, not replace**. |
| Configurable scratch/workspace folder | **Already implemented** | `SettingsService.scratchDirectory` and `ScratchFolderSelection` persist the choice; `SettingsViewController`, `SidebarViewController`, `QuickLocation`, and `MainCommand.scratchDirectory` expose it; `ScratchFolderCleanupService` handles owned cleanup semantics. Scratch-folder settings are a **foundation to extend, not replace**. |
| Keyboard focus separate from marked multi-selection | **Already implemented** | `PaneState.focusedURL` and `.markedURLs`, `PaneFocusNavigation`, `FileTableView`, and `FilePaneViewController` keep focus and operation selection distinct. `MainCommand.selectAll`, `.deselectAll`, `.invertSelection`, pattern selection commands, and same-extension selection commands are routed by `MainCommandRouter`. |
| Normal open, Open With, Finder reveal, metadata information, and system Quick Look | **Already implemented** | `MainCommand.open`, `.openWith`, `.reveal`, `.getInfo`, and `.quickLook` are focused-item routes executed by `MainWindowViewController`; `OpenWithApplicationDiscovering` and `NSWorkspaceOpenWithApplicationDiscovery` supply application choices. `Return` is normal Open and Space is system Quick Look. This does **not** constitute the deferred internal viewer. |
| Create file/folder and single-item rename | **Already implemented** | `MainCommand.newFile`, `.newFolder`, and `.rename` call the corresponding `FileOperationServicing` entry points (`createFile`, `createFolder`, and `rename`) through `MainWindowViewController`; `FileNameValidator` validates names. F2 is Rename. |
| Copy/move between panes with progress, cancellation, preflight, and conflict choices | **Already implemented** | `MainCommand.copy`, `.move`, and `.cancelOperation` route through `MainWindowViewController` to `FileOperationService`; `FileOperationRequest`, `FileOperationProgress`, `FileConflictResolution`, and `FileOperationResult` model the safe operation lifecycle. `SandboxFileAccessPolicy` validates both ends and `FileSystemOperationScheduler` schedules work. |
| Clipboard copy/cut/paste and drag/drop using the same operation path | **Already implemented** | `MainCommand.copyToClipboard`, `.cutToClipboard`, and `.pasteFromClipboard` use `FileClipboard`; `FilePaneViewController` adapts drag/drop; `MainWindowViewController` ultimately submits transfers to `FileOperationService` rather than mutating directly. |
| Trash/permanent delete with confirmation policy | **Already implemented** | `MainCommand.trash` is routed by `MainCommandRouter`; `MainWindowViewController` selects `FileOperationService.trash` or `.delete` according to `SettingsService.permanentlyDeleteInsteadOfTrash` and confirmation preferences. Emptying Trash is a separate deferred feature. |
| Conservative undo for eligible completed operations | **Partially implemented** | `MainCommand.undo`, `FileOperationRecovery`, `MainCommandRouter`, and `FileOperationService.undo` cover eligible copy/move/rename recovery only. This is intentionally not presented as a general filesystem transaction history. |
| Duplicate in place with collision-safe naming | **Already implemented** | `MainCommand.duplicate` is routed by `MainCommandRouter` and executed by `MainWindowViewController` via `FileOperationService.copy`, preserving conflict handling, progress, cancellation, and policy checks. |
| Hidden-file visibility | **Already implemented** | `PaneState.showsHiddenFiles`, `FilePaneViewModel`, and `FileSystemService` implement it; `MainCommand.toggleHiddenFiles` changes the active pane and `SettingsService.showHiddenFilesByDefault` supplies the default. |
| Fast per-pane name filtering / quick search | **Already implemented** | `PaneState.searchQuery`, `QuickSearch`, `FilePaneViewModel`, and `FilePaneViewController` implement active-pane filtering and focus-only/filter presentation; `SettingsService.quickSearchMatchMode` and `.quickSearchPresentation` persist options. Basic per-pane filtering is a **foundation to extend, not replace**. |
| Bounded recursive descendant name search | **Partially implemented** | `MainCommand.searchDescendants` invokes `DescendantSearchService`, whose `DescendantSearchLimits` and `DescendantSearchResult` bound depth, items, time, cancellation, and inaccessible paths. It is not yet the advanced recursive search described under P1. |
| Per-pane deterministic sorting | **Already implemented** | `FileSortDescriptor` carries the existing four-stage pipeline—`key`, `ascending`, `comparisonMode`, and `foldersFirst`—and `FileSystemService` applies it. `FileSortKey` supports Name, Extension, Kind, Size, Modified, Created, Added, and Accessed; `MainCommand.sortBy…`, `.sortAscending`, and `.sortDescending` route changes. This **existing four-key sorting pipeline is a foundation to extend, not replace**. |
| Safe access to local, removable, network, and granted folders | **Already implemented** | `SandboxFileAccessPolicy` is the common browse/mutation gate; `FolderAccessGrantService` persists security-scoped grants; `FileSystemProbeService`, `VolumeDiscoveryService`, and `FileOperationService` report availability/read-only failures. No new P0 behavior should bypass these services. |
| Archive browsing/extraction and archive creation/compression | **Deliberately deferred** | No `MainCommand` or service entry point exists. Product approval requires traversal/symlink/archive-bomb limits, sandbox validation, conflict resolution, cancellation, and partial-failure reporting in `FileOperationService`; shell commands are not a substitute. |
| Empty Trash | **Deliberately deferred** | No `MainCommand` or `FileOperationService` entry point exists. It remains deferred pending per-volume inventory, explicit bounds, irreversible confirmation, cancellation, sandbox validation, and partial-failure reporting. |
| Batch rename | **Deliberately deferred** | Only `MainCommand.rename` and `FileOperationService.rename` for a single item exist. Batch rename waits for a previewable atomic-or-recoverable plan, collision handling, cancellation, and confirmation. |
| Virtual or remote filesystem providers | **Deliberately deferred** | `FileSystemService`, `VolumeDiscoveryService`, and `SandboxFileAccessPolicy` support filesystem URLs that macOS has mounted or made locally available; there is no provider abstraction for FTP/SFTP/object storage or virtual panels. |
| Process view and administrator/root mode | **Deliberately deferred** | Neither behavior has a `MainCommand`, model, or service. `TerminalService`/`TerminalViewController` are an opt-in terminal and must not be interpreted as a process manager or privilege-escalation mechanism. |
| Internal streamed viewer and external-tool/editor workflows | **Deliberately deferred** | System `MainCommand.quickLook`, normal `.open`, and `.openWith` exist, but there is no internal viewer service/controller and no persisted external-tool template model/service. The P1 design directions below do not move these into P0. |

There are no unintentional **Missing** P0 rows in this audit: the known absent
orthodox features above are explicitly deferred, and the two incomplete areas are
called out as partial rather than being implied by adjacent features.

## P1 directions (concise)

### Per-pane tabs

Add a tab collection independently to each pane, with every tab owning a directory,
focus/marks, filter, sort descriptor, hidden-file state, and `NavigationHistory`.
Extend `PaneState`, `FilePaneViewModel`, and `FilePaneViewController`; do not replace
the existing pane model or history. `MainCommand.newTab` should be added only after
the Command-T migration decision below is approved.

### Advanced recursive search

Build on `DescendantSearchService` and basic `FilePaneViewModel` filtering with
scoped roots, glob/regex and metadata predicates, result streaming, explicit limits,
cancellation, inaccessible-path reporting, and an open/reveal-in-pane result route.
Keep all roots and result actions behind `SandboxFileAccessPolicy`.

### Streamed read-only text/hex/Quick Look viewer

Design an internal, read-only viewer controller backed by a bounded streaming
service: text with encoding detection, hex for binary/unknown content, and a system
Quick Look fallback/option. It must not read an entire large file into memory and
must retain an access scope only for the viewing session. This is future **Internal
Viewer** work, distinct from today's `MainCommand.quickLook`.

### External editor/tool templates

Add typed, persisted templates through `SettingsService` (application/executable,
argument placeholders, working-directory rule, and file-count policy), with a
previewed argv and no implicit shell evaluation. Validate target and working
directory access through `SandboxFileAccessPolicy`; keep normal `MainCommand.open`
and existing `NSWorkspaceOpenWithApplicationDiscovery` as the safe defaults.

### Brief / List / Gallery modes

Retain `FilePaneViewModel`, `FileItem`, selection/focus semantics, filtering, and the
four-stage `FileSortDescriptor` pipeline as the shared data source. Add per-pane
presentation state and native AppKit renderers: compact multi-column **Brief**,
metadata-rich **List** (today's foundation), and thumbnail-backed **Gallery** with
bounded asynchronous thumbnail loading.

## Shortcut migration proposal (product decision required)

Do **not** silently change P0 shortcuts. Before assigning **Command-T** to **New
Tab**, migrate the current `MainCommand.togglePaneLayout` shortcut provisionally to
**Shift-Command-P** in `MainCommandShortcutRegistry`, menus, command-bar/help text,
localization, accessibility descriptions, and shortcut tests. The final layout
shortcut and the discoverability treatment (menu wording, tooltip/help, and a
one-time migration note if warranted) are product decisions, not implementation
cleanup.

Reserve the orthodox function-key contract for the eventual commands:

| Key | Reserved behavior | Current state / migration implication |
| --- | --- | --- |
| Command-T | New Tab | Currently toggles pane layout; unavailable until the migration decision is approved. |
| Shift-Command-P | Pane-layout toggle (provisional) | Proposal only; not a silent P0 shortcut change. |
| F2 | Rename | Already `MainCommand.rename`; retain it. |
| F3 | Internal Viewer | Currently aliases `MainCommand.open`; reclaim only when the internal viewer ships, with release-note/help discoverability. |
| F4 | External Editor | Currently aliases `MainCommand.open`; reclaim only with a safe editor/template workflow and explicit migration communication. |
| Return | Normal Open | Already `MainCommand.open`; retain it and do not overload it with viewer/editor behavior. |

## Explicit deferral register

The following are expressly outside P0: **archive browsing/extraction, compression,
Trash emptying, batch rename, virtual filesystems, remote filesystems, process view,
administrator mode, the internal viewer, and external editor/tool templates**.
“Deferred” means no placeholder command that appears to work, no shell-command
shortcut around `FileOperationService`, and no weakening of `SandboxFileAccessPolicy`.
Viewer and external-tool work have P1 design notes above, but remain deferred until
their safety, resource-bounding, shortcut-migration, and discoverability decisions
are approved.
