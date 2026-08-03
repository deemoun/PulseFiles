#!/usr/bin/env bash
set -euo pipefail

SIGNED_APP="artifacts/release/PulseFiles.app"
UI_ARTIFACTS_DIR=""
SKIP_UI_HARNESS=false
BUILD_RELEASE=false
RUN_DEBUG_MUTATION_HARNESS=false
SECURITY_EVIDENCE=""

usage() {
  cat <<EOF_USAGE
Usage: scripts/release_validation.sh [--signed-app PATH] [--ui-artifacts-dir PATH]
                                     [--security-evidence PATH] [--build]
                                     [--skip-ui-harness] [--run-debug-mutation-harness]

Runs PulseFiles release validation checks:
  1. swift test
  2. release packaging stale-resource regression check
  3. optional signed, notarized distributable packaging when --build is passed
  4. signature, hardened-runtime, notarization, staple, and digest verification
  5. non-mutating signed-app UI smoke harness (unless skipped)
  6. optional disposable DEBUG mutation harness only when explicitly requested

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
    --security-evidence)
      [[ $# -ge 2 ]] || { echo "Missing value for --security-evidence" >&2; exit 64; }
      SECURITY_EVIDENCE="$2"
      shift
      ;;
    --skip-ui-harness)
      SKIP_UI_HARNESS=true
      ;;
    --run-debug-mutation-harness)
      RUN_DEBUG_MUTATION_HARNESS=true
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

echo "==> Checking deterministic clean release packaging"
scripts/test_release_packaging.sh

if [[ "${BUILD_RELEASE}" == true ]]; then
  echo "==> Building signed, notarized distributable app bundle"
  scripts/build_release_app.sh --distribute
fi

record_release_security_evidence() {
  local app_path="$1"
  local archive_path
  archive_path="$(dirname "${app_path}")/PulseFiles.zip"
  local digest_path="${archive_path}.sha256"
  local signature_details

  [[ -d "${app_path}" ]] || { echo "Signed app was not found: ${app_path}" >&2; return 66; }
  [[ -f "${archive_path}" && -f "${digest_path}" ]] || {
    echo "Final release archive or digest is missing beside ${app_path}." >&2
    return 66
  }

  echo "==> Signature verification"
  codesign --verify --deep --strict --verbose=2 "${app_path}"
  signature_details="$(codesign --display --verbose=4 "${app_path}" 2>&1)"
  printf '%s\n' "${signature_details}" | sed -n '/^Authority=/p'
  printf '%s\n' "${signature_details}" | grep -F 'Authority=Developer ID Application:' >/dev/null || {
    echo "Developer ID Application authority is missing from the app signature." >&2
    return 1
  }
  printf '%s\n' "${signature_details}" | grep -Eq '^flags=.*runtime' || {
    echo "Hardened runtime flag is missing from the app signature." >&2
    return 1
  }
  printf '%s\n' "Hardened runtime: enabled"

  echo "==> Notarization and Gatekeeper assessment"
  spctl --assess --type execute --verbose=2 "${app_path}"
  echo "Notarization result: Gatekeeper assessment accepted"

  echo "==> Staple verification"
  xcrun stapler validate "${app_path}"
  echo "Staple verification: valid"

  echo "==> Final artifact digest"
  (cd "$(dirname "${archive_path}")" && shasum -a 256 -c "$(basename "${digest_path}")")
  cat "${digest_path}"
}

if [[ -n "${SECURITY_EVIDENCE}" ]]; then
  mkdir -p "$(dirname "${SECURITY_EVIDENCE}")"
  record_release_security_evidence "${SIGNED_APP}" 2>&1 | tee "${SECURITY_EVIDENCE}"
else
  record_release_security_evidence "${SIGNED_APP}"
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

if [[ "${RUN_DEBUG_MUTATION_HARNESS}" == true ]]; then
  echo "==> Running opt-in disposable DEBUG mutation harness (not release evidence)"
  qa/ui-harness/run_debug_disposable_ui_runner.sh --workflows all
fi
