# QA matrix: destructive and mutating file operations

Use this matrix for manual release QA and focused exploratory testing of operations that can mutate or destroy data. Every scenario must use disposable folders and files created specifically for the test run.

## Scope and implementation references

Primary implementation areas under test:

- `PulseFiles/Services/FileOperationService.swift` — copy, move, rename, trash, permanent delete, conflict handling, cancellation, progress, and cleanup reporting.
- `PulseFiles/Services/SandboxFileAccessPolicy.swift` — validation of readable/writable access, experimental sandbox restrictions, explicit folder grants, and security-scoped access.
- `PulseFiles/App/MainWindowViewController.swift` — menu, command bar, paste, drag/drop, confirmation dialogs, conflict dialogs, operation progress, and cancel routing.

## Safety rules for every run

1. Create a fresh disposable root such as `/tmp/PulseFiles-QA-$(date +%Y%m%d-%H%M%S)`.
2. Never point either pane at a real project, home directory, cloud-sync directory, or removable drive containing user data.
3. Populate test data from generated files only. Suggested commands:

   ```sh
   ROOT="$(mktemp -d /tmp/PulseFiles-QA.XXXXXX)"
   mkdir -p "$ROOT/src" "$ROOT/dst" "$ROOT/protected" "$ROOT/volume-a" "$ROOT/volume-b"
   printf 'alpha\n' > "$ROOT/src/alpha.txt"
   printf 'conflict-source\n' > "$ROOT/src/conflict.txt"
   printf 'conflict-destination\n' > "$ROOT/dst/conflict.txt"
   mkdir -p "$ROOT/src/folder" "$ROOT/src/BundleLike.app/Contents" "$ROOT/src/Package.pkg/Contents"
   printf 'nested\n' > "$ROOT/src/folder/nested.txt"
   printf 'bundle\n' > "$ROOT/src/BundleLike.app/Contents/info.txt"
   printf 'package\n' > "$ROOT/src/Package.pkg/Contents/info.txt"
   ln -s "$ROOT/src/alpha.txt" "$ROOT/src/alpha-symlink.txt"
   mkfile -n 512m "$ROOT/src/large-copy.bin"
   ```

4. For cross-volume coverage, prefer two disposable APFS disk images. If unavailable, use two temporary folders and mark the result as partial coverage because it does not exercise true cross-volume behavior.
5. Clean up the root and any disk images after recording results.

## Environment matrix

Run the operation scenarios across these environment dimensions when practical:

| Dimension | Required coverage | Notes |
| --- | --- | --- |
| Build mode | Debug unrestricted, Debug experimental sandbox enabled, Release | Sandbox-specific failures should only occur when the sandbox or macOS access rules require them. |
| Entry point | Menu/keyboard, command bar, clipboard paste, drag/drop | At minimum, run one successful copy/move and one conflict case through each available entry point. |
| Destination | Same folder root, other pane root, protected folder after grant, cross-volume destination | Do not use real user folders. |
| Selection shape | Single file, multiple files, folder tree, package-like directory, symlink/alias | Include names with spaces and mixed case where possible. |
| Confirmation preference | Confirm enabled, confirm disabled | Destructive delete should still remain safety-oriented and clear. |

## Operation scenario matrix

| ID | Scenario | Disposable setup | Steps | Expected result | Implementation focus |
| --- | --- | --- | --- | --- | --- |
| MUT-001 | Copy file on same volume | `src/alpha.txt`, empty `dst/` on same temporary root | Select `alpha.txt` in source pane, copy to destination pane. | `dst/alpha.txt` exists with identical contents; original remains; progress/result shows success. | `FileOperationService.copy`, `MainWindowViewController` copy routing. |
| MUT-002 | Move file on same volume | `src/move-me.txt`, empty `dst/` | Move selected file to destination pane. | Destination exists; source no longer exists; panes refresh; no cleanup warning. | `FileOperationService.move`, source cleanup behavior. |
| MUT-003 | Copy folder tree on same volume | `src/folder/nested.txt` | Copy `folder` to `dst/`. | Entire tree exists under `dst/folder`; source tree remains. | Recursive progress and copy semantics. |
| MUT-004 | Move folder tree on same volume | `src/folder-to-move/nested.txt` | Move folder to `dst/`. | Tree exists in destination; original folder is gone. | Move preflight and destination validation. |
| MUT-005 | Copy across volumes | Source in disposable disk image A, destination in disposable disk image B | Copy selected file and folder from A to B. | Destination contains complete copies; source remains; progress completes even when copy is slower. | Cross-volume copy path, progress. |
| MUT-006 | Move across volumes | Source in disk image A, destination in disk image B | Move selected file and folder from A to B. | Destination contains complete items; source items are removed only after successful copy; cleanup warning appears if source cleanup fails. | Cross-volume move and cleanup reporting. |
| MUT-007 | Rename regular file | `src/rename-file.txt` | Rename to `renamed-file.txt`. | File exists with new name; old name gone; contents preserved. | `FileOperationService.rename`, UI rename flow. |
| MUT-008 | Rename folder | `src/RenameFolder/nested.txt` | Rename folder to `RenamedFolder`. | Folder and nested contents are preserved under new name. | Folder rename handling. |
| MUT-009 | Rename package-like directory | `src/BundleLike.app`, `src/Package.pkg` | Rename package-like directory to a new basename with same extension, then to a new extension-preserving name as appropriate. | Package directory contents are preserved; UI treats mutation safely. | Rename with directory/package semantics. |
| MUT-010 | Case-only rename | `src/CaseName.txt` | Rename to `casename.txt`, then back to `CaseName.txt`. | Rename succeeds on case-insensitive APFS/HFS+ without reporting destination conflict against itself; only one file exists. | Name comparison and destination preflight. |
| MUT-011 | Trash single file | `src/trash-me.txt` | Choose Move to Trash and confirm. | Item disappears from source pane and is recoverable from macOS Trash when supported; no permanent removal warning is shown. | `trash`, confirmation text. |
| MUT-012 | Permanent delete single file | `src/delete-me.txt` | Enable/use permanent delete path and confirm. | Item is removed immediately; confirmation warns it cannot be restored from Trash. | `delete`, destructive confirmation. |
| MUT-013 | Cancel delete confirmation | `src/keep-me.txt` | Invoke trash/permanent delete, then cancel confirmation. | File remains unchanged; operation does not start. | Confirmation cancellation routing. |
| MUT-014 | Conflict replace | `src/conflict.txt`, `dst/conflict.txt` with different contents | Copy/move source to destination and choose Replace. | Destination content matches source; source remains for copy and is removed for move; replacement is atomic/safe. | `FileConflictResolution.replace`, safe replacement. |
| MUT-015 | Conflict skip | Same as MUT-014 | Choose Skip. | Destination original content is unchanged; source remains; result records skipped item. | `FileConflictResolution.skip`, result reporting. |
| MUT-016 | Conflict cancel | Same as MUT-014 plus a second non-conflicting source | Choose Cancel when conflict dialog appears. | No further items are processed after cancellation; completed earlier items remain reported; conflicted item is unchanged. | `FileConflictResolution.cancel`, partial result display. |
| MUT-017 | Multiple conflict decisions | Three sources where two conflict in destination | Choose Replace for first conflict and Skip for second. | First destination replaced; second destination unchanged; non-conflicting items copied/moved. | Per-item conflict handling. |
| MUT-018 | Symlink copy | `src/alpha-symlink.txt` points to disposable target | Copy symlink to destination. | Copied item preserves expected symlink behavior for macOS `FileManager.copyItem`; target outside disposable root is never used. | Symlink behavior and access validation. |
| MUT-019 | Symlink move | Disposable symlink in source | Move symlink to destination. | Symlink is moved; original symlink path gone; target file remains unchanged. | Move behavior for links. |
| MUT-020 | Alias file copy/move | Create a Finder alias to a disposable target inside root | Copy and move the alias file. | Alias file is copied/moved as an alias file; target is not mutated. | Alias treatment as file data. |
| MUT-021 | Protected folder denied | Create destination not readable/writable by current process or outside experimental sandbox without grant | Attempt copy/move/delete into or from protected folder. | Operation is blocked before mutation with an access error; no partial writes occur. | `SandboxFileAccessPolicy.validateAccess`, `validateDestinationAccess`. |
| MUT-022 | Protected folder user approval | Same protected/outside folder, then grant access through the app approval flow | Retry copy/move after granting access. | Operation succeeds only after explicit approval; grant is scoped to selected folder. | `requestAccess`, folder grant flow. |
| MUT-023 | Security-scoped grant persistence after relaunch | Grant disposable outside-sandbox folder, quit app, relaunch | Open the granted folder and perform a harmless copy within it. | Access works after relaunch without requiring a second approval; revocation/reset removes access. | Grant persistence and relaunch behavior. |
| MUT-024 | Cancellation during large copy | `src/large-copy.bin` or a large folder tree | Start copy, press Command-Period/cancel while progress is active. | Operation stops promptly; result indicates cancellation; completed items are accurate; no corrupt completed file is presented as success. | Operation task cancellation and progress UI. |
| MUT-025 | Cancellation during large move | Large disposable file/folder across volumes | Start move, cancel during copy phase. | Source remains unless item was fully completed; destination partials are either absent or clearly reported as cleanup warnings/failures. | Cross-volume move cancellation. |
| MUT-026 | Cleanup after partial copy failure | Make one destination path unwritable or inject a conflict/permission failure after earlier items complete | Copy multiple selected items. | Earlier successful items remain; failed item is reported; no unrelated files are removed. | Partial failure reporting. |
| MUT-027 | Cleanup after partial move failure | Move multiple items where one source cleanup or destination write fails | Execute move and inspect both roots. | Completed moves are reported; source cleanup failures are surfaced; destination/source state is understandable and safe. | `sourceCleanupFailed`, cleanup warnings. |
| MUT-028 | Destination-inside-source rejected | `src/parent/child` | Attempt to copy/move `parent` into `parent/child`. | Operation is rejected before mutation with a clear error. | Preflight destination-inside-source guard. |
| MUT-029 | Duplicate destination rejected | Two selected source items that would map to same destination name | Attempt copy/move into destination. | Operation is rejected before mutation; no writes occur. | Duplicate destination preflight. |
| MUT-030 | Empty selection rejected | No selected items | Invoke copy/move/delete/rename. | UI shows clear no-selection message; no operation starts. | Command routing and preflight. |

## Evidence to capture

For each scenario, record:

- Build identifier, git commit, macOS version, filesystem type, and whether the test used true separate volumes.
- Entry point used: menu/keyboard, command bar, clipboard paste, or drag/drop.
- Confirmation/conflict choices made.
- Before/after tree snapshots of the disposable source and destination roots.
- Any alert text, result summary, cleanup warning, or failure message.
- Whether cleanup removed the disposable roots and unmounted disposable disk images.

## Pass/fail criteria

A run passes only if:

1. No real user data or non-disposable folder is modified.
2. Mutations happen only after the relevant confirmation, conflict choice, and access validation.
3. Cancelled operations stop without misleading success reporting.
4. Partial failures report completed, skipped, failed, and cleanup-warning states clearly.
5. Protected/outside-sandbox folders require explicit user approval before access is persisted.
6. Relaunch behavior matches the persisted grant state.
