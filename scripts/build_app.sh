#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseFiles"
CONFIGURATION="debug"
RUN_AFTER_BUILD=false
CLEAN_ARTIFACT=false

usage() {
    cat <<EOF
Usage: scripts/build_app.sh [--release] [--run] [--clean]

Builds the SwiftPM executable and packages it as artifacts/${APP_NAME}.app.

Options:
  --release   Build the release configuration instead of debug.
  --run       Launch the app bundle after packaging.
  --clean     Remove the previous app artifact before packaging.
  -h, --help  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            CONFIGURATION="release"
            ;;
        --run)
            RUN_AFTER_BUILD=true
            ;;
        --clean)
            CLEAN_ARTIFACT=true
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
ARTIFACTS_DIR="${REPO_ROOT}/artifacts"
APP_BUNDLE="${ARTIFACTS_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MATERIALIZED_INFO_PLIST="${BUILD_PATH}/PulseFiles-Info.plist"
APP_RESOURCES_DIR="${REPO_ROOT}/PulseFiles/Resources"

if [[ "${CONFIGURATION}" == "release" ]]; then
    BUILD_CONFIGURATION_FLAG="--configuration release"
else
    BUILD_CONFIGURATION_FLAG="--configuration debug"
fi

"${SCRIPT_DIR}/release_version.sh" validate
"${SCRIPT_DIR}/release_version.sh" materialize "${MATERIALIZED_INFO_PLIST}"
echo "Packaging version $("${SCRIPT_DIR}/release_version.sh" marketing-version) (build $("${SCRIPT_DIR}/release_version.sh" build-number))"

echo "Building ${APP_NAME} (${CONFIGURATION})..."
mkdir -p "${CACHE_PATH}" "${CONFIG_PATH}" "${SECURITY_PATH}" "${CLANG_CACHE_PATH}"
(
    cd "${REPO_ROOT}"
    CLANG_MODULE_CACHE_PATH="${CLANG_CACHE_PATH}" swift build ${BUILD_CONFIGURATION_FLAG} --disable-sandbox --cache-path "${CACHE_PATH}" --config-path "${CONFIG_PATH}" --security-path "${SECURITY_PATH}"
)

EXECUTABLE_PATH="${BUILD_PATH}/${CONFIGURATION}/${APP_NAME}"
if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
    echo "Expected executable was not found at ${EXECUTABLE_PATH}" >&2
    exit 1
fi

if [[ "${CLEAN_ARTIFACT}" == true ]]; then
    echo "Cleaning previous app artifact..."
    rm -rf "${APP_BUNDLE}"
fi

echo "Packaging ${APP_BUNDLE}..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "${MATERIALIZED_INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
if [[ -d "${APP_RESOURCES_DIR}" ]]; then
    cp -R "${APP_RESOURCES_DIR}/." "${RESOURCES_DIR}/"
fi
cp "${REPO_ROOT}/LICENSE" "${RESOURCES_DIR}/LICENSE"
cp "${REPO_ROOT}/NOTICE" "${RESOURCES_DIR}/NOTICE"

for RESOURCE_BUNDLE_PATH in \
    "${BUILD_PATH}/${CONFIGURATION}/${APP_NAME}_${APP_NAME}.bundle" \
    "${BUILD_PATH}/${CONFIGURATION}/${APP_NAME}_${APP_NAME}.resources"
do
    if [[ -d "${RESOURCE_BUNDLE_PATH}" ]]; then
        rm -rf "${RESOURCES_DIR}/$(basename "${RESOURCE_BUNDLE_PATH}")"
        cp -R "${RESOURCE_BUNDLE_PATH}" "${RESOURCES_DIR}/"
    fi
done
chmod +x "${MACOS_DIR}/${APP_NAME}"

if command -v codesign >/dev/null 2>&1; then
    echo "Ad-hoc signing ${APP_NAME}.app..."
    codesign --force --sign - "${APP_BUNDLE}" >/dev/null
else
    echo "codesign not found; skipping ad-hoc signing."
fi

echo
echo "Built app bundle:"
echo "  ${APP_BUNDLE}"
echo
echo "Launch with:"
echo "  open artifacts/${APP_NAME}.app"

if [[ "${RUN_AFTER_BUILD}" == true ]]; then
    echo
    echo "Launching ${APP_NAME}.app..."
    open "${APP_BUNDLE}"
fi
