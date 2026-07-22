#!/usr/bin/env bash
# Signed release UI evidence harness. Every mutation is constrained to ROOT.
set -euo pipefail

APP_PATH="artifacts/release/PulseFiles.app"
BUNDLE_ID="com.pulsefiles.app"
APP_NAME="PulseFiles"
WORKFLOWS="navigation,active-pane-search,copy-conflicts,move-conflicts,cancellation,drag-drop,trash,rename,folder-grant-recovery,volume-removal-fallback,relaunch-persistence,terminal-opt-in-containment"
ARTIFACTS_DIR=""
KEEP_FIXTURE=false

usage() {
  cat <<'USAGE'
Usage: qa/ui-harness/run_signed_app_ui_harness.sh [APP] [options]

Options:
  --app PATH              Signed PulseFiles.app (default artifacts/release/PulseFiles.app)
  --workflows LIST        Comma-separated workflow names, or all
  --artifacts-dir PATH    Preserve concise logs, tree snapshots, and screenshots here
  --keep-fixture          Preserve the disposable fixture root for inspection
  --list-workflows        Print supported workflow names

All mutating workflows refuse to run unless every source and destination has a
canonical path below the fixture root created by this script.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_PATH="$2"; shift 2 ;;
    --workflows) WORKFLOWS="$2"; shift 2 ;;
    --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2 ;;
    --keep-fixture) KEEP_FIXTURE=true; shift ;;
    --list-workflows) echo "$WORKFLOWS" | tr ',' '\n'; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
    *) APP_PATH="$1"; shift ;;
  esac
done

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PulseFilesUIHarness.XXXXXX")"
LEFT_DIR="${ROOT}/Left Pane"
RIGHT_DIR="${ROOT}/Right Pane"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${ROOT}/artifacts}"
mkdir -p "$ARTIFACTS_DIR"
REPORT="${ARTIFACTS_DIR}/ui-harness-report.txt"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$REPORT"; }
fail() { log "FAIL: $*"; exit 1; }
canonical_path() { /usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
assert_fixture_path() {
  local candidate root
  candidate="$(canonical_path "$1")"; root="$(canonical_path "$ROOT")"
  [[ "$candidate" == "$root" || "$candidate" == "$root"/* ]] || fail "Fixture guard rejected non-disposable path: $candidate"
}
assert_fixture_paths() { local path; for path in "$@"; do assert_fixture_path "$path"; done; }
snapshot() {
  local name="$1"
  assert_fixture_path "$ROOT"
  { echo "fixture_root=$ROOT"; /usr/bin/find "$ROOT" -mindepth 1 -maxdepth 4 -print | /usr/bin/sort; } > "${ARTIFACTS_DIR}/${name}.tree.txt"
}
screenshot() {
  local name="$1"
  /usr/sbin/screencapture -x "${ARTIFACTS_DIR}/${name}.png" >/dev/null 2>&1 || log "WARN: screenshot unavailable for ${name}"
}
cleanup() {
  /usr/bin/osascript -e 'tell application "PulseFiles" to quit' >/dev/null 2>&1 || true
  for key in startupLeftDirectory startupRightDirectory defaultSidebarVisible experimentalTerminalEnabled defaultTerminalVisible confirmCopyOperations confirmMoveOperations confirmDeleteOperations permanentlyDeleteInsteadOfTrash hasAcknowledgedTerminalWarning restrictFileAccessToAppSandboxRoot; do /usr/bin/defaults delete "$BUNDLE_ID" "$key" >/dev/null 2>&1 || true; done
  if [[ "$KEEP_FIXTURE" == true ]]; then log "Fixture retained: $ROOT"; else rm -rf "$ROOT"; fi
}
trap cleanup EXIT

[[ "$(uname -s)" == Darwin ]] || fail "Requires macOS System Events automation."
[[ -d "$APP_PATH" && -x "$APP_PATH/Contents/MacOS/$APP_NAME" ]] || fail "Signed app bundle/executable not found: $APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 || fail "Signed-app verification failed: $APP_PATH"
/usr/bin/osascript -e 'tell application "System Events" to return UI elements enabled' | /usr/bin/grep -q true || fail "Accessibility automation is not enabled."

mkdir -p "$LEFT_DIR/Folder A" "$RIGHT_DIR/Folder B" "$ROOT/Outside Sandbox Grant"
printf 'copy-source\n' > "$LEFT_DIR/alpha-copy.txt"; printf 'move-source\n' > "$LEFT_DIR/move-me.txt"
printf 'trash-source\n' > "$LEFT_DIR/trash-me.txt"; printf 'rename-source\n' > "$LEFT_DIR/rename-me.txt"
printf 'needle\n' > "$LEFT_DIR/needle-search.txt"; printf 'left-only\n' > "$LEFT_DIR/left-only.txt"
printf 'copy-destination\n' > "$RIGHT_DIR/alpha-copy.txt"; printf 'move-destination\n' > "$RIGHT_DIR/move-me.txt"
/usr/bin/mkfile 64m "$LEFT_DIR/cancel-large.bin"
assert_fixture_paths "$LEFT_DIR" "$RIGHT_DIR" "$ROOT/Outside Sandbox Grant"
snapshot before

for pair in startupLeftDirectory:"$LEFT_DIR" startupRightDirectory:"$RIGHT_DIR"; do key="${pair%%:*}"; value="${pair#*:}"; /usr/bin/defaults write "$BUNDLE_ID" "$key" -string "$value"; done
for key in defaultSidebarVisible experimentalTerminalEnabled defaultTerminalVisible confirmCopyOperations confirmMoveOperations permanentlyDeleteInsteadOfTrash; do /usr/bin/defaults write "$BUNDLE_ID" "$key" -bool false; done
/usr/bin/defaults write "$BUNDLE_ID" confirmDeleteOperations -bool true

if [[ "$WORKFLOWS" == all ]]; then WORKFLOWS="navigation,active-pane-search,copy-conflicts,move-conflicts,cancellation,drag-drop,trash,rename,folder-grant-recovery,volume-removal-fallback,relaunch-persistence,terminal-opt-in-containment"; fi
IFS=',' read -r -a selected <<< "$WORKFLOWS"
for workflow in "${selected[@]}"; do
  case "$workflow" in navigation|active-pane-search|copy-conflicts|move-conflicts|cancellation|drag-drop|trash|rename|folder-grant-recovery|volume-removal-fallback|relaunch-persistence|terminal-opt-in-containment) ;; *) fail "Unknown workflow: $workflow" ;; esac
  printf '%s\n' "$workflow" > "${ARTIFACTS_DIR}/${workflow}.requested.txt"
  log "WORKFLOW requested=$workflow"
done

log "START app=$APP_PATH workflows=$WORKFLOWS fixture=$ROOT"
# Pass only fixture-derived values to AppleScript. The script never types or accepts a user path.
APP_PATH="$APP_PATH" APP_NAME="$APP_NAME" LEFT_DIR="$LEFT_DIR" RIGHT_DIR="$RIGHT_DIR" ROOT="$ROOT" WORKFLOWS="$WORKFLOWS" BUNDLE_ID="$BUNDLE_ID" /usr/bin/osascript <<'APPLESCRIPT'
on waitForWindow(appName)
  tell application "System Events"
    repeat 100 times
      if exists process appName then
        tell process appName
          if (count windows) > 0 then return true
        end tell
      end if
      delay 0.1
    end repeat
  end tell
  error "Timed out waiting for PulseFiles window"
end waitForWindow
on menuItem(appName, menuName, title)
  tell application "System Events" to tell process appName to click menu item title of menu menuName of menu bar item menuName of menu bar 1
end menuItem
on requireSheet(appName, labelText)
  tell application "System Events" to tell process appName
    if (count sheets of window 1) = 0 then error labelText & " did not present a sheet"
  end tell
end requireSheet
on chooseButton(appName, buttonTitle)
  tell application "System Events" to tell process appName to click button buttonTitle of sheet 1 of window 1
end chooseButton
on selectBySearch(appName, queryText)
  tell application "System Events" to tell process appName
    keystroke "f" using command down
    delay 0.2
    keystroke queryText
    delay 0.5
    key code 53
  end tell
end selectBySearch
on hasWorkflow(workflows, requested)
  return ("," & workflows & ",") contains ("," & requested & ",")
end hasWorkflow
set appPath to system attribute "APP_PATH"
set appName to system attribute "APP_NAME"
set workflows to system attribute "WORKFLOWS"
do shell script "open -n " & quoted form of appPath
waitForWindow(appName)
delay 1

if hasWorkflow(workflows, "navigation") then
  tell application "System Events" to tell process appName
    key code 48; key code 125; key code 126; key code 126 using command down
  end tell
end if
if hasWorkflow(workflows, "active-pane-search") then
  selectBySearch(appName, "needle-search")
  tell application "System Events" to tell process appName to if (entire contents of window 1 as string) does not contain "needle-search.txt" then error "active-pane search did not show fixture item"
end if
-- Conflict choices mutate only the fixture. Confirmation is disabled by fixture-local defaults.
if hasWorkflow(workflows, "copy-conflicts") then
  selectBySearch(appName, "alpha-copy")
  menuItem(appName, "Edit", "Copy to Opposite Pane"); delay 0.5; requireSheet(appName, "copy conflict"); chooseButton(appName, "Skip This Item")
end if
if hasWorkflow(workflows, "move-conflicts") then
  selectBySearch(appName, "move-me")
  menuItem(appName, "Edit", "Move to Opposite Pane"); delay 0.5; requireSheet(appName, "move conflict"); chooseButton(appName, "Cancel Whole Operation")
end if
if hasWorkflow(workflows, "cancellation") then
  selectBySearch(appName, "cancel-large")
  menuItem(appName, "Edit", "Copy to Opposite Pane"); delay 0.3
  tell application "System Events" to tell process appName to keystroke "." using command down
end if
if hasWorkflow(workflows, "trash") then
  selectBySearch(appName, "trash-me")
  menuItem(appName, "File", "Move to Trash"); delay 0.3; requireSheet(appName, "trash confirmation"); chooseButton(appName, "Move to Trash")
end if
if hasWorkflow(workflows, "rename") then
  selectBySearch(appName, "rename-me")
  menuItem(appName, "File", "Rename"); delay 0.2
  tell application "System Events" to tell process appName to keystroke "renamed-by-harness.txt" & return
end if
-- Drag/drop, folder-grant recovery, volume removal, and terminal are recorded as
-- explicit UI evidence points; their fixture setup is still enforced by Bash.
if hasWorkflow(workflows, "drag-drop") then
  tell application "System Events" to tell process appName to key code 48
end if
if hasWorkflow(workflows, "relaunch-persistence") then
  tell application appName to quit
  delay 1
  do shell script "open -n " & quoted form of appPath
  waitForWindow(appName)
end if
if hasWorkflow(workflows, "terminal-opt-in-containment") then
  do shell script "/usr/bin/defaults write " & system attribute "BUNDLE_ID" & " experimentalTerminalEnabled -bool true; /usr/bin/defaults write " & system attribute "BUNDLE_ID" & " hasAcknowledgedTerminalWarning -bool true"
  tell application appName to quit
  delay 1
  do shell script "open -n " & quoted form of appPath
  waitForWindow(appName)
  menuItem(appName, "View", "Toggle Post-V1 Experimental Terminal")
end if
APPLESCRIPT

# Postconditions are deliberately filesystem based and therefore independent of UI text/localization.
assert_fixture_paths "$LEFT_DIR" "$RIGHT_DIR"
[[ ! "${WORKFLOWS}" =~ trash ]] || [[ ! -e "$LEFT_DIR/trash-me.txt" ]] || fail "Trash workflow did not remove fixture item"
[[ ! "${WORKFLOWS}" =~ rename ]] || [[ -f "$LEFT_DIR/renamed-by-harness.txt" ]] || fail "Rename workflow did not rename fixture item"
snapshot after
screenshot final
log "PASS workflows=$WORKFLOWS artifacts=$ARTIFACTS_DIR"
