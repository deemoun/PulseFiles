# Orthodox file-manager feature-gap audit

## Scope and status vocabulary

This audit compares the current user-facing application with a coherent, safe,
keyboard-first orthodox dual-pane experience. It is an inventory, not a promise to
copy another file manager exactly. Each row was rechecked against
`MainCommand.swift`, `MainWindowViewController.swift`, the service layer, the
README, and the approved command decisions.

- **Implemented** — the behavior has a user-facing route and the model/service
  support needed for its documented scope.
- **Partially implemented** — a usable route exists, but its documented scope or
  format coverage has a material limitation.
- **Post-V1** — intentionally outside V1; the single register at the end explains
  why.

An optional competitive enhancement is not automatically a production release
gate. Conversely, an implemented feature is not evidence that the app as a whole
is production-ready.

## Current behavior audit

| Behavior | Status | Exact evidence, scope, and conclusion |
| --- | --- | --- |
| Two independently navigable panes with an active-pane focus model | **Implemented** | `PaneID` and `PaneState` hold independent state; each pane has a `FilePaneViewModel` and `FilePaneViewController`; `MainWindowViewController` coordinates them. `MainCommand.switchPane` supplies Tab switching. |
| Per-pane tabs | **Implemented** | `PaneTabState` owns directory, focus, marks, filter, sort, hidden-file state, and `NavigationHistory`; `FilePaneViewModel` creates, closes, selects, cycles, reorders, and restores tabs. `MainCommand.newTab`, `.closeTab`, `.nextTab`, and `.previousTab` are executed for the active pane. The final tab cannot be closed. Command-T, Command-W, Control-Tab, and Control-Shift-Tab are documented routes. |
| Single-pane/dual-pane layout toggle without discarding the hidden pane | **Implemented** | `MainCommand.togglePaneLayout` is executed by `MainWindowViewController`; `SettingsService.defaultSinglePaneMode` persists the default. The completed tab shortcut migration assigns the layout toggle to Option-Command-Backslash and reserves Command-T for New Tab. |
| Swap panes, synchronize the opposite pane, and reveal the focused item opposite | **Implemented** | `MainCommand.swapPanes`, `.syncOppositePane`, and `.revealInOppositePane` are routed and executed by `MainWindowViewController`; cross-pane actions are rejected while single-pane mode makes the opposite pane unavailable. |
| Directory listing with native metadata, breadcrumbs, parent row, refresh, and filesystem change monitoring | **Implemented** | `FileItem`, `FileSystemService`, `BreadcrumbView`, `FilePaneViewController`, `FilePaneViewModel`, and `DirectoryMonitor` provide the listing and refresh lifecycle. `MainCommand.parent` and `.refresh` route navigation and reload; `SandboxFileAccessPolicy` bounds navigation. |
| Back/forward/parent navigation with per-tab history | **Implemented** | Every `PaneTabState` owns a `NavigationHistory`; `FilePaneViewModel` updates the active tab. `MainCommand.back`, `.forward`, and `.parent` execute against the active pane and tab. |
| Direct location entry and standard locations | **Implemented** | `MainCommand.goToFolder`, `.quickLocations`, `.home`, `.downloads`, `.applications`, and `.scratchDirectory` are executed by `MainWindowViewController`; `QuickLocation`, `StandardFolderAccessService`, and `SandboxFileAccessPolicy` provide selection and validation. |
| Persistent favorites/bookmarks and recent locations | **Implemented** | `BookmarkService` provides add/remove/rename/reorder persistence; `RecentLocationService` persists bounded recents; `SidebarViewController` and Quick Locations expose both. |
| Mounted-volume discovery and live mount/unmount updates | **Implemented** | `VolumeDiscoveryService` and `VolumeChangeMonitor` discover and monitor devices; the sidebar presents them, and the volume status services supply pane status. |
| Configurable scratch/workspace folder | **Implemented** | Typed `SettingsService.scratchDirectory` state is exposed by Settings, the sidebar, Quick Locations, and `MainCommand.scratchDirectory`; `ScratchFolderCleanupService` owns cleanup semantics. |
| Keyboard focus separate from marked multi-selection | **Implemented** | `PaneTabState.focusedURL` and `.markedURLs`, `PaneFocusNavigation`, `FileTableView`, and `FilePaneViewController` keep focus and operation selection distinct. Select/deselect all, inversion, pattern selection, and same-extension selection have command routes. |
| Normal Open, Open With, Finder reveal, metadata information, and system Quick Look | **Implemented** | `MainCommand.open`, `.openWith`, `.reveal`, `.getInfo`, and `.quickLook` are focused-item routes in `MainWindowViewController`; `NSWorkspaceOpenWithApplicationDiscovery` supplies application choices. Return/F4 perform normal Open and Space performs Quick Look. |
| Internal read-only viewer | **Implemented** | `MainCommand.viewer` opens `FileViewerViewController` from `MainWindowViewController`; F3 is its documented shortcut. `ReadOnlyViewerService` validates access for the session, incrementally reads a file, detects common text encodings, falls back to hex, and retains at most a 4 MiB prefix by default. It is deliberately read-only and truncates larger content rather than acting as an editor or whole-file hex tool. |
| Create file/folder and single-item rename | **Implemented** | `MainCommand.newFile`, `.newFolder`, and `.rename` reach the corresponding `FileOperationServicing` operations through `MainWindowViewController`; `FileNameValidator` validates names. F2 remains Rename. |
| Batch rename | **Implemented** | `MainCommand.batchRename` presents generated destination names and a complete preview before confirmation. `BatchRenameService` validates same-directory sources, names, duplicate destinations, and external collisions, then uses private two-phase names for cycles. Cancellation or failure triggers best-effort rollback with partial-failure warnings. The current UI offers a numbered base-name pattern, not a general regex/token transformation language. |
| Copy/move between panes with progress, cancellation, preflight, and conflict choices | **Implemented** | `MainCommand.copy`, `.move`, and `.cancelOperation` route through `MainWindowViewController` to `FileOperationService`; typed requests, progress, conflict resolution, results, access validation, and scheduling provide the safe lifecycle. |
| Clipboard copy/cut/paste and drag/drop using the same operation path | **Implemented** | Clipboard commands use `FileClipboard`; `FilePaneViewController` adapts drag/drop; `MainWindowViewController` submits transfers to `FileOperationService` instead of mutating directly. |
| Trash/permanent delete with confirmation policy | **Implemented** | `MainCommand.trash` is routed to `FileOperationService.trash` or `.delete` according to typed settings and confirmation preferences. Emptying Trash is a separate post-V1 operation. |
| Conservative undo for eligible completed operations | **Partially implemented** | `MainCommand.undo`, `FileOperationRecovery`, and `FileOperationService.undo` cover eligible copy, move, and rename recovery. PulseFiles does not claim a general filesystem transaction history or undo for every mutation. |
| Duplicate in place with collision-safe naming | **Implemented** | `MainCommand.duplicate` submits a same-directory copy through `FileOperationService`, retaining policy validation, conflict handling, progress, and cancellation. |
| Hidden-file visibility | **Implemented** | Per-tab `showsHiddenFiles`, `FilePaneViewModel`, and `FileSystemService` implement it; `MainCommand.toggleHiddenFiles` changes the active tab and typed settings supply the default. |
| Fast per-pane name filtering / quick search | **Implemented** | Per-tab `searchQuery`, `QuickSearch`, `FilePaneViewModel`, and `FilePaneViewController` implement focus-only or filtering presentation; typed settings persist match and presentation options. |
| Bounded recursive descendant search | **Implemented** | `MainCommand.searchDescendants` opens a search prompt and a results window with open, reveal, and navigate routes. `DescendantSearchService` validates roots, does not follow symbolic links, streams batches, and reports cancellation, item/depth/time limits, and inaccessible paths. |
| Advanced descendant-search predicates | **Partially implemented** | `DescendantSearchQuery` and `DescendantSearchService` already compile glob or regular-expression names plus file-kind, byte-size, modification-date, multi-scope, and recursive/nonrecursive predicates. The current `MainWindowViewController` prompt exposes only one active-pane recursive glob-fragment query, so the richer predicates and multiple scopes are service capabilities without a complete user-facing form. |
| Per-pane deterministic sorting | **Implemented** | `FileSortDescriptor` carries key, direction, comparison mode, and folders-first behavior; `FileSystemService` applies it. Name, Extension, Kind, Size, Modified, Created, Added, and Accessed keys have command/menu routes. Sort state belongs to each tab. |
| Brief / List / Gallery presentation | **Partially implemented** | Each pane has a persisted `PanePresentationMode` and an accessible selector/menu route. List displays metadata columns; Brief hides headers and metadata columns and uses compact rows; Gallery uses larger rows and a bounded, cancellable `ThumbnailLoadingService`. Brief is not an orthodox multi-column compact layout, and Gallery is not a spatial thumbnail grid, so all three choices exist but two remain simplified presentations over `NSTableView`. |
| Safe access to local, removable, network, and granted folders | **Implemented** | `SandboxFileAccessPolicy` is the shared browse/mutation gate; grant, probe, volume, and operation services report access, availability, and read-only failures. Provider-specific production claims remain subject to the release gate below. |
| ZIP creation and extraction | **Partially implemented** | `MainCommand.createArchive` and `.extractArchive` have save/confirmation/conflict UI and typed `FileOperationService` entry points backed by `ArchiveOperationService`. The in-process implementation creates ZIP entries using the stored method and extracts **stored, unencrypted ZIP entries only**; it rejects compressed or encrypted entries and does not browse archives as folders. It enforces sandbox validation, path/link/duplicate/depth/item/expanded-byte checks, staging, cancellation, progress, conflict decisions, cleanup, and partial results. This is useful ZIP support, not general archive-format or compression support. |
| Empty Trash | **Post-V1** | Intentionally unrepresented; see the single post-V1 register. |
| Virtual or remote filesystem providers | **Post-V1** | Locally mounted or macOS-provided filesystem URLs are supported, but there is no FTP/SFTP/object-storage or virtual-panel provider abstraction; see the register. |
| Process view and administrator/root mode | **Post-V1** | The opt-in terminal is neither a process manager nor a privilege-escalation mechanism; see the register. |
| External editor/tool templates | **Post-V1** | Normal Open and Open With exist, but persisted executable/argument/working-directory templates do not; see the register. |

There are no unintentional wholly missing rows in this audit. Partial rows state
the implemented slice and its actual limitation instead of classifying the whole
feature as absent.

## Production V1 release gates

These gates determine whether PulseFiles can be represented as production-ready;
they are not competitive feature requests:

1. Complete signed-app release validation and retain the required evidence from
   the release checklist.
2. Complete the storage-provider compatibility matrix for iCloud/cloud-provider
   folders, network shares, removable media, packages, symbolic links, and
   metadata preservation. Until then, the README's entries remain candidate
   behavior rather than verified support.
3. Continue to satisfy the existing destructive-operation safeguards: policy
   validation, preflight and explicit conflict/confirmation choices, bounded work,
   cancellation, cleanup, and partial-result reporting. The experimental terminal
   remains opt-in, hidden by default, and outside the file-operation safety model.

Brief's multi-column evolution, a true Gallery grid, general archive codecs,
external tool templates, provider plugins, and process-oriented panels may improve
competitiveness, but none is by itself a production release gate.

## Optional competitive follow-ups

- Expose the existing descendant-search regex, kind, size, date, scope, and
  recursion controls in an advanced search form while preserving service limits
  and `SandboxFileAccessPolicy` result routing.
- Evolve Brief into a compact multi-column renderer and Gallery into a true grid,
  retaining the current per-tab data, focus/marks, sorting, filtering, bounded
  thumbnail pipeline, and native AppKit accessibility.
- If broader archive interoperability is desired, add audited codecs and streaming
  rather than describing stored-only ZIP as general compression. Preserve the
  current archive safety limits and typed operation route.
- Broaden batch-rename transformations only behind the existing immutable preview,
  collision validation, two-phase execution, cancellation, rollback, and
  partial-failure reporting.

## Single explicit post-V1 register

The complete intentional post-V1 set is: **Empty Trash; virtual/remote filesystem
providers; process view; administrator/root mode; and external editor/tool
templates**.

- **Empty Trash** requires per-volume inventory, explicit item/byte bounds,
  irreversible confirmation, cancellation checkpoints, sandbox validation, and
  partial-failure reporting through `FileOperationService` before it can be
  exposed.
- **Virtual/remote providers** require a provider abstraction and provider-specific
  access, conflict, cancellation, and recovery semantics. Mounted filesystem URLs
  remain within the existing V1 model.
- **Process and administrator modes** are outside the app's safe file-management
  scope. The terminal must not be repackaged as either feature.
- **External editor/tool templates** require typed persistence, previewed argv with
  no implicit shell evaluation, file-count and working-directory rules, and
  `SandboxFileAccessPolicy` validation. Normal Open and Open With remain the safe
  defaults.

Post-V1 means no placeholder command, shell shortcut around
`FileOperationService`, or weakening of `SandboxFileAccessPolicy`. These entries
are optional product expansions, not blockers for production V1 unless a later
product decision explicitly promotes one.
