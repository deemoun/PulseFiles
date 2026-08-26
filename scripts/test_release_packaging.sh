#!/usr/bin/env bash
# Copyright (c) 2026 Dmitry Yarygin
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build_release_app.sh"
# shellcheck source=scripts/release_packaging.sh
source "${SCRIPT_DIR}/release_packaging.sh"

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PulseFilesReleasePackaging.XXXXXX")"
trap 'rm -rf "${FIXTURE_ROOT}"' EXIT

# Keep the entry point wired to staged assembly and publication. These static
# checks make the fixture below a regression test for the production script,
# rather than only for an otherwise-unused helper.
grep -Fq 'assemble_release_bundle "${STAGED_APP_BUNDLE}"' "${BUILD_SCRIPT}"
grep -Fq 'codesign "${CODESIGN_ARGS[@]}" "${STAGED_APP_BUNDLE}"' "${BUILD_SCRIPT}"
grep -Fq "grep -F 'Authority=Developer ID Application:'" "${BUILD_SCRIPT}"
grep -Fq 'publish_release_bundle "${STAGED_APP_BUNDLE}" "${APP_BUNDLE}"' "${BUILD_SCRIPT}"
grep -Fq 'codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"' "${BUILD_SCRIPT}"
grep -Fq 'spctl --assess --type execute --verbose=2 "${APP_BUNDLE}"' "${BUILD_SCRIPT}"
grep -Fq 'xcrun notarytool submit "${NOTARY_ARCHIVE}" --keychain-profile "${NOTARY_PROFILE}" --wait' "${BUILD_SCRIPT}"
grep -Fq 'xcrun stapler staple "${APP_BUNDLE}"' "${BUILD_SCRIPT}"
grep -Fq 'xcrun stapler validate "${APP_BUNDLE}"' "${BUILD_SCRIPT}"
grep -Fq 'shasum -a 256 "${APP_NAME}.zip"' "${BUILD_SCRIPT}"
if grep -Fq 'mkdir -p "${APP_BUNDLE}/Contents' "${BUILD_SCRIPT}"; then
    echo "Release build script must not assemble directly in the published bundle" >&2
    exit 1
fi

# Required distribution inputs are rejected before SwiftPM is invoked. Empty
# environment assignments make these checks independent of a developer shell.
if PULSEFILES_SIGN_IDENTITY= PULSEFILES_NOTARY_PROFILE= \
    "${BUILD_SCRIPT}" --distribute >"${FIXTURE_ROOT}/missing-signing.log" 2>&1; then
    echo "Distributable build succeeded without a signing identity" >&2
    exit 1
fi
grep -Fq 'requires --sign-identity' "${FIXTURE_ROOT}/missing-signing.log"

if PULSEFILES_SIGN_IDENTITY='Developer ID Application: Test' PULSEFILES_NOTARY_PROFILE= \
    "${BUILD_SCRIPT}" --distribute >"${FIXTURE_ROOT}/missing-notary.log" 2>&1; then
    echo "Distributable build succeeded without notarization credentials" >&2
    exit 1
fi
grep -Fq 'requires --notary-profile' "${FIXTURE_ROOT}/missing-notary.log"

APP_NAME="PulseFiles"
ARTIFACTS_DIR="${FIXTURE_ROOT}/artifacts/release"
PUBLISHED_BUNDLE="${ARTIFACTS_DIR}/${APP_NAME}.app"
SOURCE_RESOURCES="${FIXTURE_ROOT}/resources"
BUILD_PATH="${FIXTURE_ROOT}/build"
EXECUTABLE="${FIXTURE_ROOT}/PulseFiles"
INFO_PLIST="${FIXTURE_ROOT}/Info.plist"
REPOSITORY_ROOT="${FIXTURE_ROOT}/repository"
SENTINEL="removed-resource.txt"

mkdir -p "${ARTIFACTS_DIR}" "${SOURCE_RESOURCES}" "${BUILD_PATH}/release" "${REPOSITORY_ROOT}"
printf '#!/usr/bin/env bash\n' > "${EXECUTABLE}"
chmod +x "${EXECUTABLE}"
printf '<plist version="1.0"></plist>\n' > "${INFO_PLIST}"
printf 'fixture license\n' > "${REPOSITORY_ROOT}/LICENSE"
printf 'fixture notice\n' > "${REPOSITORY_ROOT}/NOTICE"
printf 'must not survive the next package\n' > "${SOURCE_RESOURCES}/${SENTINEL}"

package_fixture() {
    local staging_root
    staging_root="$(mktemp -d "${ARTIFACTS_DIR}/.${APP_NAME}.test.XXXXXX")"
    assemble_release_bundle \
        "${staging_root}/${APP_NAME}.app" "${APP_NAME}" "${EXECUTABLE}" \
        "${INFO_PLIST}" "${SOURCE_RESOURCES}" "${BUILD_PATH}" release "${REPOSITORY_ROOT}"
    publish_release_bundle "${staging_root}/${APP_NAME}.app" "${PUBLISHED_BUNDLE}"
    rmdir "${staging_root}"
}

package_fixture
test -f "${PUBLISHED_BUNDLE}/Contents/Resources/${SENTINEL}"
cmp "${REPOSITORY_ROOT}/LICENSE" "${PUBLISHED_BUNDLE}/Contents/Resources/LICENSE"
cmp "${REPOSITORY_ROOT}/NOTICE" "${PUBLISHED_BUNDLE}/Contents/Resources/NOTICE"

rm "${SOURCE_RESOURCES}/${SENTINEL}"
package_fixture

if [[ -e "${PUBLISHED_BUNDLE}/Contents/Resources/${SENTINEL}" ]]; then
    echo "Stale release resource survived clean packaging: ${SENTINEL}" >&2
    exit 1
fi

cmp "${REPOSITORY_ROOT}/LICENSE" "${PUBLISHED_BUNDLE}/Contents/Resources/LICENSE"
cmp "${REPOSITORY_ROOT}/NOTICE" "${PUBLISHED_BUNDLE}/Contents/Resources/NOTICE"

echo "Release packaging regression check passed"
