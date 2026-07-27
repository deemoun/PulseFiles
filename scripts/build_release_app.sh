#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseFiles"
RUN_AFTER_BUILD=false
SIGN_RELEASE=false
SIGN_IDENTITY="${PULSEFILES_SIGN_IDENTITY:-}"
ENTITLEMENTS_PATH="${PULSEFILES_ENTITLEMENTS_PATH:-}"

usage() {
    cat <<EOF_USAGE
Usage: scripts/build_release_app.sh [--run] [--clean] [--sign] [--sign-identity IDENTITY] [--entitlements PATH]

Builds the SwiftPM release executable and packages it as artifacts/release/${APP_NAME}.app.

The release bundle is unsigned by default. Signing hooks are available for future distribution
workflows, but no signing identity is required for today's local release package.

Options:
  --run                       Launch the app bundle after packaging.
  --clean                     Compatibility no-op; release packaging is always clean.
  --sign                      Sign the bundle after packaging. Requires a signing identity.
  --sign-identity IDENTITY    Signing identity to use, or set PULSEFILES_SIGN_IDENTITY.
  --entitlements PATH         Optional entitlements plist, or set PULSEFILES_ENTITLEMENTS_PATH.
  -h, --help                  Show this help.
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run)
            RUN_AFTER_BUILD=true
            ;;
        --clean)
            # Retained for existing release automation. All builds now use a
            # fresh staging bundle regardless of whether this flag is present.
            ;;
        --sign)
            SIGN_RELEASE=true
            ;;
        --sign-identity)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --sign-identity" >&2
                usage >&2
                exit 64
            fi
            SIGN_IDENTITY="$2"
            shift
            ;;
        --entitlements)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --entitlements" >&2
                usage >&2
                exit 64
            fi
            ENTITLEMENTS_PATH="$2"
            shift
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
BUILD_PATH="${REPO_ROOT}/.build"
CACHE_PATH="${BUILD_PATH}/swiftpm-cache"
CONFIG_PATH="${BUILD_PATH}/swiftpm-config"
SECURITY_PATH="${BUILD_PATH}/swiftpm-security"
CLANG_CACHE_PATH="${BUILD_PATH}/clang-module-cache"
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/release"
APP_BUNDLE="${ARTIFACTS_DIR}/${APP_NAME}.app"
MATERIALIZED_INFO_PLIST="${BUILD_PATH}/PulseFiles-Release-Info.plist"
APP_RESOURCES_DIR="${REPO_ROOT}/PulseFiles/Resources"
CONFIGURATION="release"

# shellcheck source=scripts/release_packaging.sh
source "${SCRIPT_DIR}/release_packaging.sh"

if [[ "${SIGN_RELEASE}" == true ]]; then
    if [[ -z "${SIGN_IDENTITY}" ]]; then
        echo "Release signing requested, but no signing identity was provided." >&2
        echo "Pass --sign-identity or set PULSEFILES_SIGN_IDENTITY." >&2
        exit 64
    fi
    if ! command -v codesign >/dev/null 2>&1; then
        echo "Release signing requested, but codesign was not found." >&2
        exit 69
    fi
    if [[ -n "${ENTITLEMENTS_PATH}" && ! -f "${ENTITLEMENTS_PATH}" ]]; then
        echo "Entitlements file was not found: ${ENTITLEMENTS_PATH}" >&2
        exit 66
    fi
fi

"${SCRIPT_DIR}/release_version.sh" validate
"${SCRIPT_DIR}/release_version.sh" materialize "${MATERIALIZED_INFO_PLIST}"
echo "Packaging version $("${SCRIPT_DIR}/release_version.sh" marketing-version) (build $("${SCRIPT_DIR}/release_version.sh" build-number))"

echo "Building ${APP_NAME} (${CONFIGURATION})..."
mkdir -p "${CACHE_PATH}" "${CONFIG_PATH}" "${SECURITY_PATH}" "${CLANG_CACHE_PATH}"
(
    cd "${REPO_ROOT}"
    CLANG_MODULE_CACHE_PATH="${CLANG_CACHE_PATH}" swift build --configuration release --disable-sandbox --cache-path "${CACHE_PATH}" --config-path "${CONFIG_PATH}" --security-path "${SECURITY_PATH}"
)

EXECUTABLE_PATH="${BUILD_PATH}/${CONFIGURATION}/${APP_NAME}"
if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
    echo "Expected executable was not found at ${EXECUTABLE_PATH}" >&2
    exit 1
fi

echo "Packaging ${APP_BUNDLE}..."
mkdir -p "${ARTIFACTS_DIR}"
STAGING_ROOT="$(mktemp -d "${ARTIFACTS_DIR}/.${APP_NAME}.release.XXXXXX")"
STAGED_APP_BUNDLE="${STAGING_ROOT}/${APP_NAME}.app"
cleanup_staging() {
    rm -rf "${STAGING_ROOT}"
}
trap cleanup_staging EXIT

assemble_release_bundle \
    "${STAGED_APP_BUNDLE}" \
    "${APP_NAME}" \
    "${EXECUTABLE_PATH}" \
    "${MATERIALIZED_INFO_PLIST}" \
    "${APP_RESOURCES_DIR}" \
    "${BUILD_PATH}" \
    "${CONFIGURATION}"

if [[ "${SIGN_RELEASE}" == true ]]; then
    CODESIGN_ARGS=(--force --options runtime --timestamp --sign "${SIGN_IDENTITY}")
    if [[ -n "${ENTITLEMENTS_PATH}" ]]; then
        CODESIGN_ARGS+=(--entitlements "${ENTITLEMENTS_PATH}")
    fi
    echo "Signing ${APP_NAME}.app with identity: ${SIGN_IDENTITY}"
    codesign "${CODESIGN_ARGS[@]}" "${STAGED_APP_BUNDLE}"
else
    echo "Skipping release signing. Pass --sign with --sign-identity when distribution signing is ready."
fi

publish_release_bundle "${STAGED_APP_BUNDLE}" "${APP_BUNDLE}"

echo
echo "Built release app bundle:"
echo "  ${APP_BUNDLE}"
echo
echo "Launch with:"
echo "  open artifacts/release/${APP_NAME}.app"

if [[ "${RUN_AFTER_BUILD}" == true ]]; then
    echo
    echo "Launching ${APP_NAME}.app..."
    open "${APP_BUNDLE}"
fi
