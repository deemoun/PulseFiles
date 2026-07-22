# UI automation workflows

## Signed-release smoke suite

`run_signed_app_ui_harness.sh` is the release-signoff smoke/evidence runner. It
runs only non-mutating workflows against a signed app: `navigation`,
`active-pane-search`, `copy-conflicts` (chooses **Skip This Item**),
`move-conflicts` (chooses **Cancel Whole Operation**), `drag-drop`,
`relaunch-persistence`, and `terminal-opt-in-containment`. Its temporary
fixture root exists solely for safe startup paths and observable UI content.
It does **not** run copy completion, move completion, rename, deletion, or
Trash. In particular, `FileManager.trashItem` is not fixture-contained merely
because its source is: macOS relocates the item to a system Trash location.

## DEBUG disposable runner

`run_debug_disposable_ui_runner.sh` builds `artifacts/PulseFiles.app`, launches
it with `--pulsefiles-enable-experimental-sandbox`, and uses an isolated HOME.
Each run creates `AutomationRun.*` as a new child of that configured HOME's
`Library/Application Support/PulseFiles/ExperimentalSandbox` root. Before the
app launches it canonicalizes and verifies both pane startup folders plus every
source and destination for an operation that can mutate data.

| Workflow | Behavior |
| --- | --- |
| `navigation` | Independent pane tab switching, row navigation, and parent navigation. |
| `active-pane-search` | Searches `needle-search.txt` after pane focus changes. |
| `copy-conflicts` | Chooses **Skip This Item** for a fixture conflict. |
| `move-conflicts` | Chooses **Cancel Whole Operation** for a fixture conflict. |
| `cancellation` | Starts transfer of a generated 64 MiB fixture and sends Command-Period. |
| `drag-drop` | Captures the cross-pane accessibility evidence point. |
| `rename` | Renames only `rename-me.txt` to `renamed-by-harness.txt`. |
| `relaunch-persistence` | Relaunches after fixture pane setup. |
| `terminal-opt-in-containment` | Enables the terminal only after launch; it runs no arbitrary shell command. |

The DEBUG runner deliberately has no `trash` workflow. Testing production Trash
requires equivalent OS-level isolation (for example, a disposable account or
VM), because the system Trash is outside the fixture root.
