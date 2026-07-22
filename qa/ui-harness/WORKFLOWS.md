# Disposable signed-app UI workflows

Run individual workflows with `--workflows NAME` or the complete release set
with `--workflows all`.  Each run creates a new `mktemp` root, writes startup
pane preferences only to folders below that root, captures `before.tree.txt`,
`after.tree.txt`, a concise report, and (where macOS permits) a screenshot.
Use `--artifacts-dir release-evidence/ui-<build>` to retain evidence.

| Workflow | Fixture and repeatable check |
| --- | --- |
| `navigation` | Independent pane tab switching, row navigation, and parent navigation. |
| `active-pane-search` | Searches `needle-search.txt` after pane focus changes. |
| `copy-conflicts` | Copies `alpha-copy.txt` onto a fixture conflict and chooses **Skip This Item**. |
| `move-conflicts` | Moves `move-me.txt` onto a fixture conflict and chooses **Cancel Whole Operation**. |
| `cancellation` | Starts transfer of a generated 64 MiB fixture and sends Command-Period. |
| `drag-drop` | Captures the cross-pane drag/drop accessibility evidence point; run it only against the displayed fixture panes. |
| `trash` | Confirms trash only for `trash-me.txt` beneath the fixture root. |
| `rename` | Renames only `rename-me.txt` to `renamed-by-harness.txt`. |
| `folder-grant-recovery` | Use DEBUG experimental-sandbox mode, select the generated `Outside Sandbox Grant` folder in the grant panel, then relaunch and verify recovery. Never grant a user folder. |
| `volume-removal-fallback` | Mount a disposable disk image under the fixture root, point one pane at it, detach it, and verify the pane falls back without mutation. |
| `relaunch-persistence` | Relaunches after fixture pane setup and records the persisted fixture locations. |
| `terminal-opt-in-containment` | Enables the terminal preference only after launch, toggles it, and verifies its working directory/output references the active fixture pane. Do not run arbitrary shell commands. |

## Destructive guard

The runner canonicalizes every generated source/destination and rejects anything
outside its own `mktemp` root before launch and again before postcondition
checks. It accepts no path arguments for a source, destination, grant, volume,
or terminal command. This makes a typo unable to redirect a destructive flow to
an arbitrary user path.

Some macOS privacy prompts and disk-image attach/detach timing cannot be fully
reliably driven by System Events. For the three marked workflows, retain the
artifact directory and record the visible result in the release evidence
record; a missing Accessibility entitlement is a harness failure, not a pass.
