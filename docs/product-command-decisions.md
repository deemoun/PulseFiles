# Product command decisions

| Command | Decision | Rationale |
| --- | --- | --- |
| Duplicate | V1 | A predictable same-folder copy is valuable in a keyboard-first manager. It uses `FileOperationService.copy`, asks before mutation, keeps both on collisions, supports cancellation, and validates sandbox access through the service. |
| Get Info | V1 | Read-only metadata is low risk. Access is still validated before displaying a path, type, size, or modification date. |
| Empty Trash | Post-V1 | Emptying Finder-managed Trash needs a per-volume inventory, explicit item/byte limits, irreversible-operation confirmation, cancellation checkpoints, conflict/error reporting, and sandbox validation. It is not exposed until those guarantees are implemented in `FileOperationService`. |
| Archive / Extract | Approved | Typed ZIP create/extract requests now use an in-process stored-ZIP implementation. Extraction rejects absolute/traversal paths, links, duplicates, excessive nesting and configured item/expanded-byte limits; sandbox validation, staged cleanup, preflight conflict decisions, cancellation, progress and partial results are enforced before exposure. |
| Select All | V1 | Selection-only command scoped to visible real file rows; it never selects the synthetic parent row. |
| Invert Selection | V1 | Selection-only command scoped to visible real file rows, preserving the same parent-row safety rule as Select All. |
| Batch Rename | Approved | The immutable plan previews every source/destination, validates names, rejects duplicate and external collisions, and the confirmed operation uses private two-phase names for cycles. Cancellation/failure triggers best-effort rollback and reports rollback warnings as partial failure. |
| Pane tabs and layout shortcuts | V1 | Command-T is reserved for creating a tab in the active pane, matching macOS convention. Pane layout moves to Option-Command-\\; Command-W closes a pane tab, and Control-Tab / Control-Shift-Tab cycle tabs. Closing the final tab is disabled. |

## Safety gate for post-V1 mutations

`Empty Trash` remains intentionally unrepresented. Archive create/extract and batch rename are represented only after their typed service entry points satisfied sandbox validation, bounded accounting, preview/conflict gates, cancellable progress, staged cleanup, and explicit partial-failure semantics.
