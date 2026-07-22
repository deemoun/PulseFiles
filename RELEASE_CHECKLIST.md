# PulseFiles Release Checklist

Use this checklist before publishing a PulseFiles build. Prefer testing with a clean user account or a reset `UserDefaults` domain, and use disposable folders/files for every destructive operation.

Record signed-app results with [`qa/release-evidence-template.md`](qa/release-evidence-template.md). That record is required for the macOS/architecture matrix, clean-account and upgrade coverage, and pass/fail evidence for signed-app-only scenarios.

## Required build targets

Run both command-line verification and manual app-bundle verification before release:

- [ ] `swift test` passes from the repository root.
- [ ] `./scripts/build_app.sh --release` creates `artifacts/PulseFiles.app` successfully.
- [ ] A signed release app is produced and launched outside SwiftPM.
- [ ] `scripts/release_validation.sh --signed-app artifacts/release/PulseFiles.app` runs on macOS, including the signed-app UI harness, or any skipped harness run is documented with an environment reason.

> **Signed release app required:** Scenarios involving macOS security-scoped folder grants, persisted file access, Finder/Open With behavior, app relaunch persistence, release unrestricted mode, and any behavior affected by code signing, entitlements, quarantine, or TCC must be verified on a signed release `.app`, not only with `swift run`. The external harness in `qa/ui-harness/` is the automated signed-app smoke gate for these flows and requires Accessibility permission for the invoking terminal or CI runner.

## Manual scenarios

### 1. First launch

**Run on:** signed release app and, as a smoke check, local debug app.

**Steps**

- [ ] Remove or reset prior PulseFiles preferences for the test account.
- [ ] Launch PulseFiles from the built `.app` bundle.
- [ ] Observe the initial window, panes, sidebar, command bar, menus, and toolbar state.
- [ ] Confirm no post-V1 experimental terminal is visible on first launch.

**Expected results**

- [ ] The app opens one main window and remains responsive.
- [ ] Two file panes are visible unless a persisted single-pane setting was intentionally restored.
- [ ] One pane is clearly active.
- [ ] Initial directories load without crashing or silently mutating files.
- [ ] The post-V1 experimental terminal is disabled and hidden by default.
- [ ] Closing the last window terminates the app.

### 2. Dual-pane navigation

**Run on:** signed release app preferred; debug app acceptable for basic navigation.

**Steps**

- [ ] Navigate the left pane to a folder containing subfolders and files.
- [ ] Navigate the right pane to a different folder.
- [ ] Use mouse selection, double-click, Return, Backspace, breadcrumbs, and Tab to move between panes.
- [ ] Sort each pane by Name, Size, and Modified.

**Expected results**

- [ ] Each pane keeps an independent current directory, selection, sort order, and navigation history.
- [ ] Tab switches the active pane and visual active-pane styling follows focus.
- [ ] Double-click and Return open folders/files as appropriate.
- [ ] Sorting remains folder-first and does not affect the inactive pane unexpectedly.

### 3. Parent row and Command-Up behavior

**Run on:** signed release app for sandbox boundary checks; debug app acceptable for general behavior.

**Steps**

- [ ] Navigate into a nested folder.
- [ ] Use the synthetic `..` parent row to navigate upward.
- [ ] Use Command-Up to navigate upward.
- [ ] In restricted DEBUG sandbox mode, navigate to the sandbox root and attempt to go above it using `..`, Backspace, and Command-Up.

**Expected results**

- [ ] The parent row appears only when upward navigation is allowed.
- [ ] The parent row opens the parent folder and does not behave like a normal file item.
- [ ] Command-Up navigates to the parent when allowed.
- [ ] Restricted DEBUG sandbox mode never allows parent-row, Backspace, or Command-Up navigation outside the active sandbox root.

### 4. Search/filter behavior

**Run on:** signed release app preferred; debug app acceptable.

**Steps**

- [ ] Select the left pane and enter a search query that matches only some visible files.
- [ ] Switch active panes and search in the right pane.
- [ ] Search for a query with no matches.
- [ ] Clear the search field.
- [ ] Repeat while inside a nested folder where the parent row would normally be visible.

**Expected results**

- [ ] Search applies to the active pane only.
- [ ] Matching results update promptly and preserve folder/file semantics.
- [ ] Empty-result state is clear and non-destructive.
- [ ] Clearing search restores the unfiltered listing.
- [ ] The synthetic `..` parent row is hidden while search is active.

### 5. Hidden-file toggle

**Run on:** signed release app preferred; debug app acceptable.

**Steps**

- [ ] Open a folder containing dotfiles or create a disposable hidden file such as `.pulsefiles-hidden-test`.
- [ ] Toggle hidden files on.
- [ ] Toggle hidden files off.
- [ ] Relaunch if hidden-file visibility is expected to persist for the chosen setting path.

**Expected results**

- [ ] Hidden files appear only when the toggle is enabled.
- [ ] Hidden files sort consistently with normal files.
- [ ] Toggling does not change the current folder or selection unexpectedly.
- [ ] Persisted hidden-file preference is restored after relaunch when configured as a saved setting.

### 6. Copy, move, rename, trash, and permanent delete

**Run on:** signed release app for Finder Trash and real file-manager behavior; use disposable files only.

**Steps**

- [ ] Create disposable source and destination folders.
- [ ] Copy one file from the active pane to the opposite pane.
- [ ] Move one file from the active pane to the opposite pane.
- [ ] Rename a file and a folder with valid names.
- [ ] Attempt a rename with an invalid or empty name.
- [ ] Trash a disposable file.
- [ ] Permanently delete a disposable file only after confirming the destructive prompt and test setup.

**Expected results**

- [ ] Copy leaves the original in place and creates the destination item.
- [ ] Move removes the source and creates the destination item.
- [ ] Rename updates the item in place and refreshes the pane.
- [ ] Invalid rename input is rejected before mutation.
- [ ] Trash uses macOS Trash behavior where available.
- [ ] Permanent delete is clearly confirmed, irreversible, and only affects the selected disposable item.
- [ ] File operation results report failures, partial failures, skipped items, and cleanup warnings clearly.

### 7. Conflict handling: replace, skip, cancel

**Run on:** signed release app preferred; debug app acceptable with disposable folders.

**Steps**

- [ ] Prepare a source item and a destination item with the same name but distinguishable contents.
- [ ] Start a copy or move that causes a name conflict and choose Replace.
- [ ] Recreate the conflict and choose Skip.
- [ ] Recreate the conflict and choose Cancel.
- [ ] Repeat with a folder conflict if practical.

**Expected results**

- [ ] Replace overwrites only the conflicted destination item after explicit confirmation.
- [ ] Skip preserves the existing destination item and continues other queued operations when applicable.
- [ ] Cancel stops the operation without silently overwriting remaining conflicts.
- [ ] Results distinguish replaced, skipped, cancelled, and failed items.
- [ ] Replacement failure leaves a safe, explainable state and does not silently lose both source and destination.

### 8. Operation cancellation

**Run on:** signed release app preferred; debug app acceptable. Use large disposable files or folders.

**Steps**

- [ ] Start a long-running copy or move operation.
- [ ] Observe progress UI or status reporting.
- [ ] Cancel the operation before completion.
- [ ] Inspect source and destination folders after cancellation.

**Expected results**

- [ ] Cancellation is available while the operation is in progress.
- [ ] The UI remains responsive.
- [ ] The result clearly reports cancellation.
- [ ] Completed items remain valid, incomplete items are cleaned up when possible, and cleanup warnings are visible when cleanup cannot be completed.
- [ ] No unrelated files are changed.

### 9. Sidebar shortcuts and recents

**Run on:** signed release app for persisted recents and system folders; debug app acceptable for smoke testing.

**Steps**

- [ ] Open the sidebar.
- [ ] Click built-in shortcuts such as Home, Desktop, Documents, Downloads, or other available entries.
- [ ] Navigate to several distinct folders in panes.
- [ ] Confirm recent locations update.
- [ ] Relaunch and inspect sidebar recents again.

**Expected results**

- [ ] Sidebar shortcuts navigate the active pane, not an unintended pane.
- [ ] Shortcuts unavailable because of macOS permissions fail safely with a clear prompt or error.
- [ ] Recent locations are deduplicated, bounded, and ordered by recent use.
- [ ] Recent locations persist after relaunch.

### 10. Security-scoped folder grants

**Run on:** signed release app only.

**Steps**

- [ ] Attempt to browse a protected or previously ungranted folder that requires user approval.
- [ ] Grant access through the macOS folder picker or app-provided access flow.
- [ ] Navigate within the granted folder.
- [ ] Copy, move, rename, and trash disposable items inside the granted folder if permissions allow.
- [ ] Relaunch the signed release app and revisit the granted folder.

**Expected results**

- [ ] The app requests explicit access instead of bypassing macOS permission controls.
- [ ] Granted folders are browsable and mutable according to the granted permission and operation type.
- [ ] Security-scoped access is retained across relaunch when the app is expected to persist bookmarks.
- [ ] Revoked or unavailable grants fail safely with a clear recovery path.

### 11. Restricted DEBUG sandbox mode

**Run on:** debug app launched with restricted sandbox mode, not a release-only build.

**Steps**

- [ ] Launch a DEBUG build with `--pulsefiles-enable-experimental-sandbox` or set the `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` UserDefaults key to `true`.
- [ ] Confirm panes start inside `~/Library/Application Support/PulseFiles/ExperimentalSandbox`.
- [ ] Attempt to navigate outside the sandbox root by parent navigation, typed/opened paths, sidebar shortcuts, recents, and file operations.
- [ ] Explicitly grant an outside folder through the approved access flow.
- [ ] Repeat navigation and file operations inside the granted outside folder.

**Expected results**

- [ ] Restricted mode is opt-in, driven by `ExperimentalFlags.restrictFileAccessToAppSandboxRoot`, and clearly behaves as a development/testing safeguard.
- [ ] Navigation and file operations are blocked outside the sandbox root unless an explicit folder grant exists.
- [ ] Parent navigation cannot escape the sandbox root.
- [ ] Explicit grants allow only the granted folder scope and fail safely when revoked.

### 12. Release unrestricted mode

**Run on:** signed release app only.

**Steps**

- [ ] Launch the signed release app without debug sandbox flags or debug-only sandbox preferences.
- [ ] Browse normal user folders such as Home, Desktop, Documents, and Downloads.
- [ ] Perform copy, move, rename, and trash operations on disposable files in normal user-controlled folders.
- [ ] Confirm protected locations still use macOS permission prompts where applicable.

**Expected results**

- [ ] Release builds default to normal file-manager access behavior and `ExperimentalFlags.restrictFileAccessToAppSandboxRoot` is effectively `false`.
- [ ] Normal file-manager browsing and operations work across user-approved locations.
- [ ] Access still routes through macOS permission and security-scoped grant behavior where required.
- [ ] No debug-only sandbox warning or forced sandbox root appears in normal release use.

### 13. Post-V1 experimental terminal containment

**Run on:** signed release app and debug app.

**Steps**

- [ ] Launch with reset preferences.
- [ ] Confirm terminal UI is hidden.
- [ ] Try menu, toolbar, or command-bar terminal entry points, if present.
- [ ] Enable the post-V1 experimental terminal setting intentionally.
- [ ] Toggle terminal visibility and observe the first-use warning.
- [ ] Disable the setting again and relaunch.

**Expected results**

- [ ] The post-V1 experimental terminal is disabled and hidden by default.
- [ ] Terminal entry points are visibly labeled post-V1/experimental and do not show an active shell until the experimental setting is enabled.
- [ ] First use warns that this post-V1 preview can modify or delete files and may affect files outside the experimental sandbox when restrictions are disabled.
- [ ] When enabled, the preview uses an authorized active-pane working directory; denied directories are rejected and access scopes end with the command.
- [ ] Hiding the panel or closing the window terminates an active command on a best-effort basis without claiming rollback; disabling the setting prevents the terminal from appearing after relaunch.

### 14. Settings persistence after relaunch

**Run on:** signed release app only for final release sign-off; debug app acceptable for preliminary checks.

**Steps**

- [ ] Change startup or last directories for both panes.
- [ ] Change sidebar visibility.
- [ ] Change hidden-file visibility.
- [ ] Change sort descriptor.
- [ ] Change confirmation preferences for copy, move, delete, and permanent delete if exposed.
- [ ] Change single-pane mode and file color scheme if exposed.
- [ ] Quit and relaunch the app.

**Expected results**

- [ ] Persisted settings restore accurately after relaunch.
- [ ] Settings apply to the intended pane or global surface only.
- [ ] Safety-sensitive settings, especially destructive-operation confirmations and permanent delete preference, remain clear and do not silently become less safe.
- [ ] Unavailable or moved startup folders fail safely and fall back to an accessible location.

### 15. Mounted-volume changes

**Run on:** signed release app only. Use a disposable external drive or disk image.

**Steps**

- [ ] Open the sidebar and confirm the volume appears under Devices.
- [ ] Navigate one pane into a folder on that volume, then unmount/eject it in Finder.
- [ ] If practical, start a multi-item copy involving the volume and eject it during the operation.

**Expected results**

- [ ] Devices refreshes promptly after mount and unmount events.
- [ ] A pane on the removed volume clears its stale selection and safely falls back to an accessible, policy-validated folder.
- [ ] The app does not continue mutations after the removed source or destination is detected; partial failures and any cleanup warnings are shown.

### 16. Version 1.0 storage compatibility

**Run on:** a signed release app only. Use only disposable fixtures. Run the cloud
case with a dedicated test account/provider folder, the network case with a
disposable share, and removable-media cases with a disposable disk image or
empty external volume. Record provider, filesystem, mount protocol, and macOS
version alongside each result.

**Steps**

- [ ] **Cloud folder:** copy and move a locally downloaded disposable item in iCloud Drive or another provider folder. If iCloud optimized storage can produce a cloud-only fixture, attempt the same operation before downloading it, then download it in Finder and retry.
- [ ] **Network share:** browse, copy, move, rename, and trash a disposable file on a mounted writable share. Disconnect the share before one retry.
- [ ] **Removable media:** copy to and from a writable disposable disk image/external volume, then repeat a destination attempt after mounting it read-only or ejecting it.
- [ ] **Package:** copy, move, rename, trash, and open/reveal a disposable `.app`, `.bundle`, or other package fixture; compare its tree before and after.
- [ ] **Symbolic link:** copy and move a link whose target is outside the fixture root and a self-referential directory link. Confirm the copied link retains its stored destination and no target content is copied through the link.
- [ ] **Finder alias:** create a Finder alias to a disposable target and attempt copy, move, rename, trash, and permanent delete. Confirm each requested mutation is blocked before changing the alias or target.
- [ ] **Metadata:** apply disposable permissions, timestamps, Finder tags, an extended attribute, and an ACL where supported; copy across the same filesystem and across the network/removable fixture. Inspect the destination and any result warning before removing the source.

**Expected results**

- [ ] Locally available cloud items and mounted writable network/removable volumes complete normal operations only when macOS access permits them.
- [ ] A cloud-only iCloud item is rejected before mutation with a download-and-retry recovery message. A disconnected volume asks for reconnect/remount; a read-only destination asks for writable media. No rejected scenario writes a destination item.
- [ ] Package trees remain complete for the checked operation. Symbolic links remain links and never cause traversal of an unselected target.
- [ ] Finder aliases are explicitly rejected before mutation with Finder/original-item recovery guidance; they are not presented as symbolic links.
- [ ] Standard metadata is preserved where the destination supports it. Any unsupported metadata is called out as a cleanup warning, and the source is retained until the operator verifies the destination.

## Final release sign-off

- [ ] All command-line tests passed.
- [ ] All signed-release-app-only scenarios passed on a signed `.app`.
- [ ] Signed-app evidence records cover macOS 13, macOS 14, macOS 15, and the current macOS release, with at least one Apple Silicon and one Intel run.
- [ ] Signed-app evidence includes at least one clean user account and one upgrade run from the immediately prior released version.
- [ ] All destructive scenarios used disposable files and folders.
- [ ] Sandbox, security-scoped grant, terminal, and permanent delete safety expectations were explicitly verified.
- [ ] The signed-app storage-compatibility scenarios documented above were recorded for cloud, network, removable, package, symbolic-link, Finder-alias, and metadata behavior; unsupported/partial provider behavior is reflected in release notes rather than marketed as supported.
- [ ] Any failures are documented with app version, build configuration, macOS version, reproduction steps, and whether the failure occurred in `swift run`, unsigned `.app`, or signed release `.app`.
- [ ] Every unresolved failure is a release blocker unless it is an approved documented limitation with a named owner and target release in the signed-app evidence record.
