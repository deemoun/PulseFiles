#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseFiles"
RUN_AFTER_BUILD=false
PACKAGE_MODE="local"
SIGN_IDENTITY="${PULSEFILES_SIGN_IDENTITY:-}"
ENTITLEMENTS_PATH="${PULSEFILES_ENTITLEMENTS_PATH:-}"
NOTARY_PROFILE="${PULSEFILES_NOTARY_PROFILE:-}"

usage() {
    cat <<EOF_USAGE
Usage: scripts/build_release_app.sh [--local-unsigned | --distribute] [--run] [--clean]
                                    [--sign-identity IDENTITY] [--entitlements PATH]
                                    [--notary-profile PROFILE]

Builds a clean SwiftPM release bundle. The default --local-unsigned mode writes a
development-only app to artifacts/development/unsigned-release/${APP_NAME}.app.

--distribute is the only distributable path. It requires a Developer ID signing
identity and a notarytool keychain profile, then signs with hardened runtime,
notarizes, staples, verifies Gatekeeper acceptance, and emits a final ZIP/digest
under artifacts/release.

Options:
  --local-unsigned             Build the development-only unsigned bundle (default).
  --distribute                 Build and verify a distributable signed release.
  --run                        Launch the app bundle after packaging.
  --clean                      Compatibility no-op; packaging is always clean.
  --sign-identity IDENTITY     Developer ID identity, or PULSEFILES_SIGN_IDENTITY.
  --entitlements PATH          Optional entitlements plist, or PULSEFILES_ENTITLEMENTS_PATH.
  --notary-profile PROFILE     notarytool keychain profile, or PULSEFILES_NOTARY_PROFILE.
  -h, --help                   Show this help.
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local-unsigned) PACKAGE_MODE="local" ;;
        --distribute|--sign) PACKAGE_MODE="distribute" ;;
        --run) RUN_AFTER_BUILD=true ;;
        --clean) ;;
        --sign-identity)
            [[ $# -ge 2 ]] || { echo "Missing value for --sign-identity" >&2; exit 64; }
            SIGN_IDENTITY="$2"; shift ;;
        --entitlements)
            [[ $# -ge 2 ]] || { echo "Missing value for --entitlements" >&2; exit 64; }
            ENTITLEMENTS_PATH="$2"; shift ;;
        --notary-profile)
            [[ $# -ge 2 ]] || { echo "Missing value for --notary-profile" >&2; exit 64; }
            NOTARY_PROFILE="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
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
MATERIALIZED_INFO_PLIST="${BUILD_PATH}/PulseFiles-Release-Info.plist"
APP_RESOURCES_DIR="${REPO_ROOT}/PulseFiles/Resources"
CONFIGURATION="release"

if [[ "${PACKAGE_MODE}" == "distribute" ]]; then
    ARTIFACTS_DIR="${REPO_ROOT}/artifacts/release"
    [[ -n "${SIGN_IDENTITY}" ]] || { echo "Distributable packaging requires --sign-identity or PULSEFILES_SIGN_IDENTITY." >&2; exit 64; }
    [[ -n "${NOTARY_PROFILE}" ]] || { echo "Distributable packaging requires --notary-profile or PULSEFILES_NOTARY_PROFILE." >&2; exit 64; }
    for command in codesign spctl xcrun ditto shasum; do
        command -v "${command}" >/dev/null 2>&1 || { echo "Distributable packaging requires ${command}." >&2; exit 69; }
    done
else
    ARTIFACTS_DIR="${REPO_ROOT}/artifacts/development/unsigned-release"
    if [[ -n "${SIGN_IDENTITY}" || -n "${NOTARY_PROFILE}" ]]; then
        echo "Signing/notarization inputs are ignored in --local-unsigned mode; pass --distribute." >&2
    fi
fi

if [[ -n "${ENTITLEMENTS_PATH}" && ! -f "${ENTITLEMENTS_PATH}" ]]; then
    echo "Entitlements file was not found: ${ENTITLEMENTS_PATH}" >&2
    exit 66
fi

APP_BUNDLE="${ARTIFACTS_DIR}/${APP_NAME}.app"
FINAL_ARCHIVE="${ARTIFACTS_DIR}/${APP_NAME}.zip"
FINAL_DIGEST="${FINAL_ARCHIVE}.sha256"

# shellcheck source=scripts/release_packaging.sh
source "${SCRIPT_DIR}/release_packaging.sh"

"${SCRIPT_DIR}/release_version.sh" validate
"${SCRIPT_DIR}/release_version.sh" materialize "${MATERIALIZED_INFO_PLIST}"
echo "Packaging version $("${SCRIPT_DIR}/release_version.sh" marketing-version) (build $("${SCRIPT_DIR}/release_version.sh" build-number))"

echo "Building ${APP_NAME} (${CONFIGURATION})..."
mkdir -p "${CACHE_PATH}" "${CONFIG_PATH}" "${SECURITY_PATH}" "${CLANG_CACHE_PATH}"
(
    cd "${REPO_ROOT}"
    CLANG_MODULE_CACHE_PATH="${CLANG_CACHE_PATH}" swift build --configuration release --disable-sandbox \
        --cache-path "${CACHE_PATH}" --config-path "${CONFIG_PATH}" --security-path "${SECURITY_PATH}"
)

EXECUTABLE_PATH="${BUILD_PATH}/${CONFIGURATION}/${APP_NAME}"
[[ -x "${EXECUTABLE_PATH}" ]] || { echo "Expected executable was not found at ${EXECUTABLE_PATH}" >&2; exit 1; }

mkdir -p "${ARTIFACTS_DIR}"
STAGING_ROOT="$(mktemp -d "${ARTIFACTS_DIR}/.${APP_NAME}.release.XXXXXX")"
STAGED_APP_BUNDLE="${STAGING_ROOT}/${APP_NAME}.app"
NOTARY_ARCHIVE="${STAGING_ROOT}/${APP_NAME}-notary.zip"
trap 'rm -rf "${STAGING_ROOT}"' EXIT

assemble_release_bundle "${STAGED_APP_BUNDLE}" "${APP_NAME}" "${EXECUTABLE_PATH}" \
    "${MATERIALIZED_INFO_PLIST}" "${APP_RESOURCES_DIR}" "${BUILD_PATH}" "${CONFIGURATION}"

if [[ "${PACKAGE_MODE}" == "distribute" ]]; then
    CODESIGN_ARGS=(--force --options runtime --timestamp --sign "${SIGN_IDENTITY}")
    [[ -z "${ENTITLEMENTS_PATH}" ]] || CODESIGN_ARGS+=(--entitlements "${ENTITLEMENTS_PATH}")
    echo "Signing staged bundle with hardened runtime: ${SIGN_IDENTITY}"
    codesign "${CODESIGN_ARGS[@]}" "${STAGED_APP_BUNDLE}"
    codesign --display --verbose=4 "${STAGED_APP_BUNDLE}" 2>&1 | \
        grep -F 'Authority=Developer ID Application:' >/dev/null || {
            echo "Distributable packaging requires a Developer ID Application signature." >&2
            exit 1
        }
    # Never leave an older archive looking current if a later notarization or
    # verification stage fails. Only the final successful stage recreates it.
    rm -f "${FINAL_ARCHIVE}" "${FINAL_DIGEST}"
fi

publish_release_bundle "${STAGED_APP_BUNDLE}" "${APP_BUNDLE}"

if [[ "${PACKAGE_MODE}" == "distribute" ]]; then
    echo "Verifying the published signed bundle..."
    codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

    echo "Submitting signed bundle with Apple notarytool profile: ${NOTARY_PROFILE}"
    ditto -c -k --keepParent "${APP_BUNDLE}" "${NOTARY_ARCHIVE}"
    xcrun notarytool submit "${NOTARY_ARCHIVE}" --keychain-profile "${NOTARY_PROFILE}" --wait

    echo "Stapling and validating Apple's notarization ticket..."
    xcrun stapler staple "${APP_BUNDLE}"
    xcrun stapler validate "${APP_BUNDLE}"
    codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
    echo "Assessing the notarized, stapled bundle with Gatekeeper..."
    spctl --assess --type execute --verbose=2 "${APP_BUNDLE}"

    ditto -c -k --keepParent "${APP_BUNDLE}" "${FINAL_ARCHIVE}"
    (cd "${ARTIFACTS_DIR}" && shasum -a 256 "${APP_NAME}.zip" > "${APP_NAME}.zip.sha256")
    echo "Distributable artifact is ready only after every verification above passes:"
    echo "  ${FINAL_ARCHIVE}"
    echo "  ${FINAL_DIGEST}"
else
    rm -f "${FINAL_ARCHIVE}" "${FINAL_DIGEST}"
    echo "Development-only unsigned bundle (NOT FOR DISTRIBUTION):"
    echo "  ${APP_BUNDLE}"
fi

if [[ "${RUN_AFTER_BUILD}" == true ]]; then
    open "${APP_BUNDLE}"
fi
