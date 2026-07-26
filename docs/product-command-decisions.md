# Product command decisions

| Command | Decision | Rationale |
| --- | --- | --- |
| Duplicate | V1 | A predictable same-folder copy is valuable in a keyboard-first manager. It uses `FileOperationService.copy`, asks before mutation, keeps both on collisions, supports cancellation, and validates sandbox access through the service. |
| Get Info | V1 | Read-only metadata is low risk. Access is still validated before displaying a path, type, size, or modification date. |
| Empty Trash | Post-V1 | Emptying Finder-managed Trash needs a per-volume inventory, explicit item/byte limits, irreversible-operation confirmation, cancellation checkpoints, conflict/error reporting, and sandbox validation. It is not exposed until those guarantees are implemented in `FileOperationService`. |
| Archive / Extract | Post-V1 | Archive parsing and extraction must defend against path traversal, symlinks, archive bombs, per-entry and total byte/item limits, conflict choices, cancellation, and sandbox validation. No shell archive command is exposed. |
| Select All | V1 | Selection-only command scoped to visible real file rows; it never selects the synthetic parent row. |
| Invert Selection | V1 | Selection-only command scoped to visible real file rows, preserving the same parent-row safety rule as Select All. |
| Batch Rename | Post-V1 | Requires a previewable, atomic-or-recoverable rename plan, collision handling, cancellation semantics, and clear confirmation. Single-item rename remains the V1 safe path. |
| Pane tabs and layout shortcuts | V1 | Command-T is reserved for creating a tab in the active pane, matching macOS convention. Pane layout moves to Option-Command-\\; Command-W closes a pane tab, and Control-Tab / Control-Shift-Tab cycle tabs. Closing the final tab is disabled. |

## Safety gate for post-V1 mutations

`Empty Trash`, archive, and extract are intentionally not represented as commands or menu entries yet. Their implementation may only be approved when their `FileOperationService` entry points enforce sandbox validation, bounded resource accounting, conflict resolution, cancellable progress, and partial-failure reporting before any mutation occurs.
