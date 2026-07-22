#!/usr/bin/env bash
set -euo pipefail

SIGNED_APP="artifacts/release/PulseFiles.app"
UI_ARTIFACTS_DIR=""
SKIP_UI_HARNESS=false
BUILD_RELEASE=false

usage() {
  cat <<EOF_USAGE
Usage: scripts/release_validation.sh [--signed-app PATH] [--ui-artifacts-dir PATH] [--build] [--skip-ui-harness]

Runs PulseFiles release validation checks:
  1. swift test
  2. optional release app packaging via scripts/build_release_app.sh --clean when --build is passed
  3. non-mutating signed-app UI smoke harness against the supplied .app bundle (unless skipped), preserving release evidence when requested

The non-mutating UI smoke harness requires macOS Accessibility automation permission and a valid signed app.
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --signed-app)
      [[ $# -ge 2 ]] || { echo "Missing value for --signed-app" >&2; exit 64; }
      SIGNED_APP="$2"
      shift
      ;;
    --ui-artifacts-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --ui-artifacts-dir" >&2; exit 64; }
      UI_ARTIFACTS_DIR="$2"
      shift
      ;;
    --build)
      BUILD_RELEASE=true
      ;;
    --skip-ui-harness)
      SKIP_UI_HARNESS=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

echo "==> Running Swift tests"
swift test

echo "==> Validating release version metadata"
scripts/release_version.sh validate

if [[ "${BUILD_RELEASE}" == true ]]; then
  echo "==> Building release app bundle"
  scripts/build_release_app.sh --clean
fi

if [[ "${SKIP_UI_HARNESS}" == true ]]; then
  echo "==> Skipping signed-app UI harness"
else
  echo "==> Running signed-app UI harness"
  if [[ -n "${UI_ARTIFACTS_DIR}" ]]; then
    qa/ui-harness/run_signed_app_ui_harness.sh "${SIGNED_APP}" --workflows all --artifacts-dir "${UI_ARTIFACTS_DIR}"
  else
    qa/ui-harness/run_signed_app_ui_harness.sh "${SIGNED_APP}" --workflows all
  fi
fi
