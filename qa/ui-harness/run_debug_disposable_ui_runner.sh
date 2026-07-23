#!/usr/bin/env bash
# DEBUG-only disposable automation runner. Every mutation is constrained to ROOT.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

APP_PATH="artifacts/PulseFiles.app"
BUNDLE_ID="com.pulsefiles.app"
APP_NAME="PulseFiles"
WORKFLOWS="navigation,active-pane-search,copy-conflicts,move-conflicts,cancellation,drag-drop,rename,relaunch-persistence,terminal-opt-in-containment"
ARTIFACTS_DIR=""
KEEP_FIXTURE=false

usage() {
  cat <<'USAGE'
Usage: qa/ui-harness/run_debug_disposable_ui_runner.sh [options]

Options:
  --workflows LIST        Comma-separated workflow names, or all
  --artifacts-dir PATH    Preserve concise logs, tree snapshots, and screenshots here
  --keep-fixture          Preserve the disposable fixture root for inspection
  --list-workflows        Print supported workflow names

Builds the DEBUG app, enables the experimental sandbox, and creates its fixture
root below the configured experimental sandbox root. No external app/path input
is accepted. Every startup, mutating source, and mutating destination must
canonicalize beneath that per-run child before launch.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflows) WORKFLOWS="$2"; shift 2 ;;
    --artifacts-dir) ARTIFACTS_DIR="$2"; shift 2 ;;
    --keep-fixture) KEEP_FIXTURE=true; shift ;;
    --list-workflows) echo "$WORKFLOWS" | tr ',' '\n'; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
    *) echo "Unexpected argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

# Use an isolated home so preferences and the configured experimental root are
# disposable. The top-level automation command can supply both locations; it
# remains responsible for removing locations it supplied.
CALLER_MANAGES_LOCATIONS=false
if [[ -n "${PULSEFILES_AUTOMATION_PREFERENCES_HOME:-}" || -n "${PULSEFILES_AUTOMATION_FIXTURE_ROOT:-}" ]]; then
  [[ -n "${PULSEFILES_AUTOMATION_PREFERENCES_HOME:-}" && -n "${PULSEFILES_AUTOMATION_FIXTURE_ROOT:-}" ]] || { echo "Both PULSEFILES_AUTOMATION_PREFERENCES_HOME and PULSEFILES_AUTOMATION_FIXTURE_ROOT are required together." >&2; exit 64; }
  PREFERENCES_HOME="${PULSEFILES_AUTOMATION_PREFERENCES_HOME}"
  ROOT="${PULSEFILES_AUTOMATION_FIXTURE_ROOT}"
  CALLER_MANAGES_LOCATIONS=true
else
  PREFERENCES_HOME="$(mktemp -d "${TMPDIR:-/tmp}/PulseFilesDebugRunnerHome.XXXXXX")"
fi
SANDBOX_ROOT="${PULSEFILES_AUTOMATION_SANDBOX_ROOT:-${PREFERENCES_HOME}/Library/Application Support/PulseFiles/ExperimentalSandbox}"
mkdir -p "$SANDBOX_ROOT"
if [[ "${CALLER_MANAGES_LOCATIONS}" == false ]]; then
  ROOT="$(mktemp -d "${SANDBOX_ROOT}/AutomationRun.XXXXXX")"
else
  mkdir -p "$ROOT"
fi
LEFT_DIR="${ROOT}/Left Pane"
RIGHT_DIR="${ROOT}/Right Pane"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/${APP_NAME}"
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
  if [[ "$KEEP_FIXTURE" == true || "$CALLER_MANAGES_LOCATIONS" == true ]]; then
    log "Fixture retained: $ROOT"
  else
    rm -rf "$PREFERENCES_HOME"
  fi
}
trap cleanup EXIT

[[ "$(uname -s)" == Darwin ]] || fail "Requires macOS System Events automation."
scripts/build_app.sh --clean
[[ -d "$APP_PATH" && -x "$APP_EXECUTABLE" ]] || fail "DEBUG app bundle/executable not found after build: $APP_PATH"
/usr/bin/osascript -e 'tell application "System Events" to return UI elements enabled' | /usr/bin/grep -q true || fail "Accessibility automation is not enabled."

mkdir -p "$LEFT_DIR/Folder A" "$RIGHT_DIR/Folder B" "$ROOT/Outside Sandbox Grant" "$PREFERENCES_HOME/Library/Preferences"
printf 'copy-source\n' > "$LEFT_DIR/alpha-copy.txt"; printf 'move-source\n' > "$LEFT_DIR/move-me.txt"
printf 'rename-source\n' > "$LEFT_DIR/rename-me.txt"
printf 'needle\n' > "$LEFT_DIR/needle-search.txt"; printf 'left-only\n' > "$LEFT_DIR/left-only.txt"
printf 'copy-destination\n' > "$RIGHT_DIR/alpha-copy.txt"; printf 'move-destination\n' > "$RIGHT_DIR/move-me.txt"
/usr/bin/mkfile 64m "$LEFT_DIR/cancel-large.bin"
# Validate every pane startup and every path an automation workflow can mutate
# before the app process exists. This is deliberately stricter than checking a
# fixture source: FileManager.trashItem may relocate an item outside its source
# tree, so this runner never invokes the production Trash workflow.
MUTATING_SOURCES=("$LEFT_DIR/alpha-copy.txt" "$LEFT_DIR/move-me.txt" "$LEFT_DIR/cancel-large.bin" "$LEFT_DIR/rename-me.txt")
MUTATING_DESTINATIONS=("$RIGHT_DIR/alpha-copy.txt" "$RIGHT_DIR/move-me.txt" "$RIGHT_DIR/cancel-large.bin" "$LEFT_DIR/renamed-by-harness.txt")
assert_fixture_paths "$LEFT_DIR" "$RIGHT_DIR" "$ROOT/Outside Sandbox Grant" "${MUTATING_SOURCES[@]}" "${MUTATING_DESTINATIONS[@]}"
[[ "$(canonical_path "$ROOT")" == "$(canonical_path "$SANDBOX_ROOT")"/* ]] || fail "Run root is not beneath configured experimental sandbox root"
snapshot before

# All harness preferences are written only into the per-run CFPreferences home.
# This intentionally includes the complete set of keys the harness changes, so
# neither normal completion nor an interrupted run can alter the user's domain.
for pair in startupLeftDirectory:"$LEFT_DIR" startupRightDirectory:"$RIGHT_DIR"; do
  key="${pair%%:*}"; value="${pair#*:}"
  /usr/bin/env CFFIXED_USER_HOME="$PREFERENCES_HOME" HOME="$PREFERENCES_HOME" /usr/bin/defaults write "$BUNDLE_ID" "$key" -string "$value"
done
for key in defaultSidebarVisible experimentalTerminalEnabled defaultTerminalVisible confirmCopyOperations confirmMoveOperations permanentlyDeleteInsteadOfTrash; do
  /usr/bin/env CFFIXED_USER_HOME="$PREFERENCES_HOME" HOME="$PREFERENCES_HOME" /usr/bin/defaults write "$BUNDLE_ID" "$key" -bool false
done
/usr/bin/env CFFIXED_USER_HOME="$PREFERENCES_HOME" HOME="$PREFERENCES_HOME" /usr/bin/defaults write "$BUNDLE_ID" confirmDeleteOperations -bool true
/usr/bin/env CFFIXED_USER_HOME="$PREFERENCES_HOME" HOME="$PREFERENCES_HOME" /usr/bin/defaults write "$BUNDLE_ID" restrictFileAccessToAppSandboxRoot -bool true

if [[ "$WORKFLOWS" == all ]]; then WORKFLOWS="navigation,active-pane-search,copy-conflicts,move-conflicts,cancellation,drag-drop,rename,relaunch-persistence,terminal-opt-in-containment"; fi
IFS=',' read -r -a selected <<< "$WORKFLOWS"
for workflow in "${selected[@]}"; do
  case "$workflow" in navigation|active-pane-search|copy-conflicts|move-conflicts|cancellation|drag-drop|rename|relaunch-persistence|terminal-opt-in-containment) ;; *) fail "Unknown workflow: $workflow" ;; esac
  printf '%s\n' "$workflow" > "${ARTIFACTS_DIR}/${workflow}.requested.txt"
  log "WORKFLOW requested=$workflow"
done

log "START debug_app=$APP_PATH workflows=$WORKFLOWS sandbox_root=$SANDBOX_ROOT fixture=$ROOT preferences_home=$PREFERENCES_HOME"
# Pass only fixture-derived values to AppleScript. The script never types or accepts a user path.
APP_EXECUTABLE="$APP_EXECUTABLE" APP_NAME="$APP_NAME" LEFT_DIR="$LEFT_DIR" RIGHT_DIR="$RIGHT_DIR" ROOT="$ROOT" WORKFLOWS="$WORKFLOWS" BUNDLE_ID="$BUNDLE_ID" PREFERENCES_HOME="$PREFERENCES_HOME" /usr/bin/osascript <<'APPLESCRIPT'
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
set appExecutable to system attribute "APP_EXECUTABLE"
set appName to system attribute "APP_NAME"
set workflows to system attribute "WORKFLOWS"
set preferencesHome to system attribute "PREFERENCES_HOME"
on launchIsolatedApp(appExecutable, preferencesHome)
  do shell script "/usr/bin/env CFFIXED_USER_HOME=" & quoted form of preferencesHome & " HOME=" & quoted form of preferencesHome & " " & quoted form of appExecutable & " --pulsefiles-enable-experimental-sandbox >/dev/null 2>&1 &"
end launchIsolatedApp
launchIsolatedApp(appExecutable, preferencesHome)
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
if hasWorkflow(workflows, "rename") then
  selectBySearch(appName, "rename-me")
  menuItem(appName, "File", "Rename"); delay 0.2
  tell application "System Events" to tell process appName to keystroke "renamed-by-harness.txt" & return
end if
-- Drag/drop and terminal are recorded as explicit UI evidence points; their
-- fixture setup is still enforced by Bash.
if hasWorkflow(workflows, "drag-drop") then
  tell application "System Events" to tell process appName to key code 48
end if
if hasWorkflow(workflows, "relaunch-persistence") then
  tell application appName to quit
  delay 1
  launchIsolatedApp(appExecutable, preferencesHome)
  waitForWindow(appName)
end if
if hasWorkflow(workflows, "terminal-opt-in-containment") then
  do shell script "/usr/bin/env CFFIXED_USER_HOME=" & quoted form of preferencesHome & " HOME=" & quoted form of preferencesHome & " /usr/bin/defaults write " & quoted form of (system attribute "BUNDLE_ID") & " experimentalTerminalEnabled -bool true; /usr/bin/env CFFIXED_USER_HOME=" & quoted form of preferencesHome & " HOME=" & quoted form of preferencesHome & " /usr/bin/defaults write " & quoted form of (system attribute "BUNDLE_ID") & " hasAcknowledgedTerminalWarning -bool true"
  tell application appName to quit
  delay 1
  launchIsolatedApp(appExecutable, preferencesHome)
  waitForWindow(appName)
  menuItem(appName, "View", "Toggle Experimental Terminal")
end if
APPLESCRIPT

# Postconditions are deliberately filesystem based and therefore independent of UI text/localization.
assert_fixture_paths "$LEFT_DIR" "$RIGHT_DIR"
[[ ! "${WORKFLOWS}" =~ rename ]] || [[ -f "$LEFT_DIR/renamed-by-harness.txt" ]] || fail "Rename workflow did not rename fixture item"
snapshot after
screenshot final
log "PASS workflows=$WORKFLOWS artifacts=$ARTIFACTS_DIR"
