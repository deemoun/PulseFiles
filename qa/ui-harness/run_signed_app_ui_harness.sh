#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-artifacts/release/PulseFiles.app}"
BUNDLE_ID="com.pulsefiles.app"
APP_NAME="PulseFiles"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PulseFilesUIHarness.XXXXXX")"
LEFT_DIR="${ROOT}/Left Pane"
RIGHT_DIR="${ROOT}/Right Pane"
REPORT="${ROOT}/ui-harness-report.txt"

cleanup() {
  /usr/bin/osascript -e 'tell application "PulseFiles" to quit' >/dev/null 2>&1 || true
  for key in startupLeftDirectory startupRightDirectory defaultSidebarVisible experimentalTerminalEnabled defaultTerminalVisible confirmCopyOperations confirmMoveOperations confirmDeleteOperations permanentlyDeleteInsteadOfTrash hasAcknowledgedTerminalWarning; do
    /usr/bin/defaults delete "${BUNDLE_ID}" "${key}" >/dev/null 2>&1 || true
  done
  rm -rf "${ROOT}"
}
trap cleanup EXIT

log() { printf '%s\n' "$*" | tee -a "${REPORT}"; }
fail() { log "FAIL: $*"; exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "PulseFiles UI harness requires macOS because it drives AppKit through System Events."
fi

[[ -d "${APP_PATH}" ]] || fail "App bundle not found: ${APP_PATH}"
[[ -x "${APP_PATH}/Contents/MacOS/${APP_NAME}" ]] || fail "Executable not found in ${APP_PATH}"

if ! /usr/bin/codesign --verify --deep --strict "${APP_PATH}" >/dev/null 2>&1; then
  fail "${APP_PATH} is not a valid signed app bundle; build/sign it before release UI validation."
fi

if ! /usr/bin/osascript -e 'tell application "System Events" to return UI elements enabled' | /usr/bin/grep -q true; then
  fail "Enable Accessibility automation for Terminal/CI runner in System Settings before running this harness."
fi

mkdir -p "${LEFT_DIR}/Folder A" "${RIGHT_DIR}/Folder B"
printf 'alpha\n' > "${LEFT_DIR}/alpha-copy.txt"
printf 'move\n' > "${LEFT_DIR}/move-me.txt"
printf 'delete\n' > "${LEFT_DIR}/delete-me.txt"
printf 'needle\n' > "${LEFT_DIR}/needle-search.txt"
printf 'hidden\n' > "${LEFT_DIR}/ordinary.txt"
printf 'destination\n' > "${RIGHT_DIR}/destination.txt"

/usr/bin/defaults write "${BUNDLE_ID}" startupLeftDirectory -string "${LEFT_DIR}"
/usr/bin/defaults write "${BUNDLE_ID}" startupRightDirectory -string "${RIGHT_DIR}"
/usr/bin/defaults write "${BUNDLE_ID}" defaultSidebarVisible -bool true
/usr/bin/defaults write "${BUNDLE_ID}" experimentalTerminalEnabled -bool false
/usr/bin/defaults write "${BUNDLE_ID}" defaultTerminalVisible -bool false
/usr/bin/defaults write "${BUNDLE_ID}" confirmCopyOperations -bool true
/usr/bin/defaults write "${BUNDLE_ID}" confirmMoveOperations -bool true
/usr/bin/defaults write "${BUNDLE_ID}" confirmDeleteOperations -bool true
/usr/bin/defaults write "${BUNDLE_ID}" permanentlyDeleteInsteadOfTrash -bool false

log "Starting signed-app UI harness against ${APP_PATH}"
log "Disposable fixture root: ${ROOT}"

/usr/bin/osascript <<APPLESCRIPT
on waitForProcess(processName, shouldExist, timeoutSeconds)
  tell application "System Events"
    repeat with i from 1 to (timeoutSeconds * 10)
      set existsNow to exists process processName
      if existsNow is shouldExist then return true
      delay 0.1
    end repeat
  end tell
  error "Timed out waiting for process " & processName & " existence=" & shouldExist
end waitForProcess

on waitForWindow(processName, timeoutSeconds)
  tell application "System Events"
    repeat with i from 1 to (timeoutSeconds * 10)
      if exists process processName then
        tell process processName
          if (count of windows) > 0 then return true
        end tell
      end if
      delay 0.1
    end repeat
  end tell
  error "Timed out waiting for main window"
end waitForWindow

on pressMenu(processName, menuName, itemName)
  tell application "System Events" to tell process processName
    click menu item itemName of menu menuName of menu bar item menuName of menu bar 1
  end tell
end pressMenu

-- A cancelled confirmation only proves the command path was exercised when a
-- sheet was actually presented.  Keep this assertion next to every destructive
-- command so a navigation or selection regression cannot turn the test into a
-- false-positive no-op.
on requireSheet(processName, operationName)
  tell application "System Events" to tell process processName
    if (count of sheets of window 1) = 0 then error operationName & " did not present its confirmation sheet"
  end tell
end requireSheet

on assertWindowContains(processName, expectedText)
  tell application "System Events" to tell process processName
    set windowDescription to entire contents of window 1 as string
    if windowDescription does not contain expectedText then error "Window did not contain expected text: " & expectedText
  end tell
end assertWindowContains

set appPath to "${APP_PATH}"
set appName to "${APP_NAME}"

do shell script "open -n " & quoted form of appPath
waitForProcess(appName, true, 10)
waitForWindow(appName, 10)
delay 1
assertWindowContains(appName, "needle-search.txt")

-- Active pane switching and keyboard navigation.
tell application "System Events" to tell process appName
  key code 48 -- Tab switches active pane.
  delay 0.2
  key code 48
  delay 0.2
  key code 125 -- Down arrow exercises table navigation.
  delay 0.2
  key code 126 -- Up arrow exercises table navigation.
  delay 0.2
  key code 126 using command down -- parent-folder keyboard shortcut should be handled safely.
end tell

-- Search/filter through the toolbar search shortcut/field.
tell application "System Events" to tell process appName
  keystroke "f" using command down
  delay 0.2
  keystroke "needle"
  delay 0.5
end tell
assertWindowContains(appName, "needle-search.txt")
tell application "System Events" to tell process appName
  keystroke "a" using command down
  key code 51
  delay 0.3
end tell

-- Sidebar navigation: toggle visibility. Do not navigate to Home here: the
-- destructive-flow fixture below intentionally remains selected in Left Pane.
pressMenu(appName, "View", "Toggle Sidebar")
delay 0.3
pressMenu(appName, "View", "Toggle Sidebar")
delay 0.3

-- Command bar invocation. Escape closes it without mutating files.
tell application "System Events" to tell process appName
  keystroke "k" using command down
  delay 0.3
  keystroke "view"
  delay 0.3
  key code 53
end tell

-- Terminal disabled state: toggle should not show terminal when disabled.
pressMenu(appName, "View", "Toggle Terminal")
delay 0.5

-- Confirmation flows: invoke copy/move/delete and cancel dialogs so disposable files are not changed by the harness.
tell application "System Events" to tell process appName
  keystroke "f" using command down
  delay 0.2
  keystroke "alpha-copy"
  delay 0.4
  key code 53
  delay 0.1
end tell
pressMenu(appName, "Edit", "Copy to Opposite Pane")
delay 0.5
requireSheet(appName, "Copy")
tell application "System Events" to tell process appName
  key code 53
end tell

tell application "System Events" to tell process appName
  keystroke "f" using command down
  delay 0.2
  keystroke "move-me"
  delay 0.4
  key code 53
  delay 0.1
end tell
pressMenu(appName, "Edit", "Move to Opposite Pane")
delay 0.5
requireSheet(appName, "Move")
tell application "System Events" to tell process appName
  key code 53
end tell

tell application "System Events" to tell process appName
  keystroke "f" using command down
  delay 0.2
  keystroke "delete-me"
  delay 0.4
  key code 53
  delay 0.1
end tell
pressMenu(appName, "File", "Move to Trash")
delay 0.5
requireSheet(appName, "Move to Trash")
tell application "System Events" to tell process appName
  key code 53
end tell

-- Enable terminal preference and verify the toggle path can be invoked. The app may show its first-use warning.
do shell script "/usr/bin/defaults write ${BUNDLE_ID} experimentalTerminalEnabled -bool true; /usr/bin/defaults write ${BUNDLE_ID} hasAcknowledgedTerminalWarning -bool true"
tell application appName to quit
waitForProcess(appName, false, 10)
do shell script "open -n " & quoted form of appPath
waitForProcess(appName, true, 10)
waitForWindow(appName, 10)
delay 1
pressMenu(appName, "View", "Toggle Terminal")
delay 0.7

-- Close-last-window termination.
tell application "System Events" to tell process appName
  keystroke "w" using command down
end tell
waitForProcess(appName, false, 10)
APPLESCRIPT

[[ -f "${LEFT_DIR}/alpha-copy.txt" ]] || fail "Copy confirmation cancellation unexpectedly removed source file."
[[ -f "${LEFT_DIR}/move-me.txt" ]] || fail "Move confirmation cancellation unexpectedly removed source file."
[[ -f "${LEFT_DIR}/delete-me.txt" ]] || fail "Delete confirmation cancellation unexpectedly removed source file."

log "PASS: signed-app UI harness completed."
