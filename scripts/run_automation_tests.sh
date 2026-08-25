#!/usr/bin/env bash
# Safe, disposable entry point for PulseFiles automation tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

skip_system_events=false
skip_system_events_reason=""

usage() {
  cat <<'EOF'
Usage: scripts/run_automation_tests.sh [--skip-system-events]

Options:
  --skip-system-events  Run Swift unit and AppKit UI tests, but skip the
                        external System Events mutation harness. Intended for
                        CI runners without Accessibility permission.

Environment:
  PULSEFILES_SKIP_SYSTEM_EVENTS=1  Same as --skip-system-events.
EOF
}

for argument in "$@"; do
  case "$argument" in
    --skip-system-events)
      skip_system_events=true
      skip_system_events_reason="--skip-system-events was requested"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown option: $argument"
      ;;
  esac
done

if [[ "${PULSEFILES_SKIP_SYSTEM_EVENTS:-0}" == "1" ]]; then
  skip_system_events=true
  skip_system_events_reason="PULSEFILES_SKIP_SYSTEM_EVENTS=1"
elif [[ "${PULSEFILES_CI_SAFE_MODE:-0}" == "1" ]]; then
  # Retain the older CI setting for existing callers while making the
  # System Events behavior explicit in the preferred flag above.
  skip_system_events=true
  skip_system_events_reason="PULSEFILES_CI_SAFE_MODE=1 (legacy CI-safe mode)"
fi

PREFERENCES_HOME="$(mktemp -d "${TMPDIR:-/tmp}/PulseFilesAutomationPreferences.XXXXXX")"
SANDBOX_ROOT="${PREFERENCES_HOME}/Library/Application Support/PulseFiles/ExperimentalSandbox"
mkdir -p "$SANDBOX_ROOT"
FIXTURE_ROOT="$(mktemp -d "${SANDBOX_ROOT}/AutomationRun.XXXXXX")"

canonical_path() { /usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
assert_fixture_path() {
  local candidate root
  candidate="$(canonical_path "$1")"
  root="$(canonical_path "$FIXTURE_ROOT")"
  [[ "$candidate" == "$root" || "$candidate" == "$root"/* ]] || fail "Refusing a destructive UI workflow outside this run's fixture root: $candidate"
}
cleanup() {
  # These are mktemp-created, per-run paths. Never remove their parents: that
  # would risk user defaults, Application Support, or the system Trash.
  assert_fixture_path "$FIXTURE_ROOT"
  rm -rf "$FIXTURE_ROOT"
  rm -rf "$PREFERENCES_HOME"
}
trap cleanup EXIT

assert_fixture_path "$FIXTURE_ROOT"
[[ "$(canonical_path "$FIXTURE_ROOT")" == "$(canonical_path "$SANDBOX_ROOT")"/* ]] || fail "Fixture root must be inside the isolated DEBUG sandbox"

export HOME="$PREFERENCES_HOME"
export CFFIXED_USER_HOME="$PREFERENCES_HOME"
export PULSEFILES_AUTOMATION_PREFERENCES_HOME="$PREFERENCES_HOME"
export PULSEFILES_AUTOMATION_SANDBOX_ROOT="$SANDBOX_ROOT"
export PULSEFILES_AUTOMATION_FIXTURE_ROOT="$FIXTURE_ROOT"

echo "==> Running architecture boundary regression tests"
scripts/test_validate_architecture.sh

if [[ "$(uname -s)" == Darwin ]]; then
  # Make the DEBUG-only sandbox restriction explicit for both in-process UI
  # tests and the separately launched DEBUG application.
  /usr/bin/defaults write com.pulsefiles.app restrictFileAccessToAppSandboxRoot -bool true
fi

echo "==> Running deterministic PulseFiles service and unit tests with disposable preferences and fixture paths"
swift test -c debug --filter PulseFilesTests

if [[ "$(uname -s)" != Darwin ]]; then
  echo "==> Skipping AppKit UI automation (macOS only)"
  exit 0
fi

echo "==> Running AppKit UI target with DEBUG sandbox configuration"
swift test -c debug --filter PulseFilesAppKitUITests

# System Events requires macOS Accessibility permission, which hosted runners
# do not grant. The explicit CI mode deliberately retains the Swift and
# in-process AppKit coverage above while omitting only this external mutation
# harness.
if [[ "$skip_system_events" == true ]]; then
  echo "==> Skipping System Events mutation harness: $skip_system_events_reason"
  exit 0
fi

# The mutation-capable System Events runner accepts only fixture-derived paths.
# Reassert the boundary immediately before invoking it, including every
# canonical source/destination path it creates for its destructive workflows.
MUTATION_PATHS=(
  "$FIXTURE_ROOT/Left Pane/alpha-copy.txt"
  "$FIXTURE_ROOT/Left Pane/move-me.txt"
  "$FIXTURE_ROOT/Left Pane/cancel-large.bin"
  "$FIXTURE_ROOT/Left Pane/rename-me.txt"
  "$FIXTURE_ROOT/Left Pane/renamed-by-harness.txt"
  "$FIXTURE_ROOT/Right Pane/alpha-copy.txt"
  "$FIXTURE_ROOT/Right Pane/move-me.txt"
  "$FIXTURE_ROOT/Right Pane/cancel-large.bin"
)
for path in "${MUTATION_PATHS[@]}"; do assert_fixture_path "$path"; done

echo "==> Running disposable DEBUG UI automation"
qa/ui-harness/run_debug_disposable_ui_runner.sh --workflows all
