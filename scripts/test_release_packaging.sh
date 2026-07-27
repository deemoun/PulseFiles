#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build_release_app.sh"
# shellcheck source=scripts/release_packaging.sh
source "${SCRIPT_DIR}/release_packaging.sh"

# Keep the entry point wired to staged assembly and publication. These static
# checks make the fixture below a regression test for the production script,
# rather than only for an otherwise-unused helper.
grep -Fq 'assemble_release_bundle \' "${BUILD_SCRIPT}"
grep -Fq 'codesign "${CODESIGN_ARGS[@]}" "${STAGED_APP_BUNDLE}"' "${BUILD_SCRIPT}"
grep -Fq 'publish_release_bundle "${STAGED_APP_BUNDLE}" "${APP_BUNDLE}"' "${BUILD_SCRIPT}"
if grep -Fq 'mkdir -p "${APP_BUNDLE}/Contents' "${BUILD_SCRIPT}"; then
    echo "Release build script must not assemble directly in the published bundle" >&2
    exit 1
fi

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/PulseFilesReleasePackaging.XXXXXX")"
trap 'rm -rf "${FIXTURE_ROOT}"' EXIT

APP_NAME="PulseFiles"
ARTIFACTS_DIR="${FIXTURE_ROOT}/artifacts/release"
PUBLISHED_BUNDLE="${ARTIFACTS_DIR}/${APP_NAME}.app"
SOURCE_RESOURCES="${FIXTURE_ROOT}/resources"
BUILD_PATH="${FIXTURE_ROOT}/build"
EXECUTABLE="${FIXTURE_ROOT}/PulseFiles"
INFO_PLIST="${FIXTURE_ROOT}/Info.plist"
SENTINEL="removed-resource.txt"

mkdir -p "${ARTIFACTS_DIR}" "${SOURCE_RESOURCES}" "${BUILD_PATH}/release"
printf '#!/usr/bin/env bash\n' > "${EXECUTABLE}"
chmod +x "${EXECUTABLE}"
printf '<plist version="1.0"></plist>\n' > "${INFO_PLIST}"
printf 'must not survive the next package\n' > "${SOURCE_RESOURCES}/${SENTINEL}"

package_fixture() {
    local staging_root
    staging_root="$(mktemp -d "${ARTIFACTS_DIR}/.${APP_NAME}.test.XXXXXX")"
    assemble_release_bundle \
        "${staging_root}/${APP_NAME}.app" "${APP_NAME}" "${EXECUTABLE}" \
        "${INFO_PLIST}" "${SOURCE_RESOURCES}" "${BUILD_PATH}" release
    publish_release_bundle "${staging_root}/${APP_NAME}.app" "${PUBLISHED_BUNDLE}"
    rmdir "${staging_root}"
}

package_fixture
test -f "${PUBLISHED_BUNDLE}/Contents/Resources/${SENTINEL}"

rm "${SOURCE_RESOURCES}/${SENTINEL}"
package_fixture

if [[ -e "${PUBLISHED_BUNDLE}/Contents/Resources/${SENTINEL}" ]]; then
    echo "Stale release resource survived clean packaging: ${SENTINEL}" >&2
    exit 1
fi

echo "Release packaging regression check passed"
