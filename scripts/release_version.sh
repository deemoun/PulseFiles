#!/usr/bin/env bash
# Copyright (c) 2026 Dmitry Yarygin
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/release/VERSION"
INFO_TEMPLATE="${REPO_ROOT}/PulseFiles/Info.plist"
RELEASE_NOTES="${REPO_ROOT}/RELEASE_NOTES.md"

value_for() { sed -n "s/^$1=//p" "${VERSION_FILE}" | head -n 1; }

load_version() {
    [[ -f "${VERSION_FILE}" ]] || { echo "Missing release version file: ${VERSION_FILE}" >&2; exit 66; }
    MARKETING_VERSION="$(value_for MARKETING_VERSION)"
    BUILD_NUMBER="$(value_for BUILD_NUMBER)"
    LICENSE_IDENTIFIER="$(value_for LICENSE_IDENTIFIER)"
    [[ "${MARKETING_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || { echo "MARKETING_VERSION must be a semantic version." >&2; exit 65; }
    [[ "${BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]] || { echo "BUILD_NUMBER must be a positive integer for CFBundleVersion." >&2; exit 65; }
    [[ "${LICENSE_IDENTIFIER}" == "GPL-3.0-or-later" ]] || { echo "LICENSE_IDENTIFIER must be GPL-3.0-or-later." >&2; exit 65; }
}

validate() {
    load_version
    grep -Fq '<string>$(PULSEFILES_MARKETING_VERSION)</string>' "${INFO_TEMPLATE}" || { echo "Info.plist does not consume MARKETING_VERSION." >&2; exit 65; }
    grep -Fq '<string>$(PULSEFILES_BUILD_NUMBER)</string>' "${INFO_TEMPLATE}" || { echo "Info.plist does not consume BUILD_NUMBER." >&2; exit 65; }
    grep -Fq "<!-- release-version: ${MARKETING_VERSION}; build-number: ${BUILD_NUMBER}; license-identifier: ${LICENSE_IDENTIFIER} -->" "${RELEASE_NOTES}" || { echo "RELEASE_NOTES.md does not match release/VERSION." >&2; exit 65; }
}

materialize() {
    [[ $# -eq 1 ]] || { echo "Usage: $0 materialize OUTPUT_PATH" >&2; exit 64; }
    validate
    sed -e "s/\$(PULSEFILES_MARKETING_VERSION)/${MARKETING_VERSION}/g" -e "s/\$(PULSEFILES_BUILD_NUMBER)/${BUILD_NUMBER}/g" "${INFO_TEMPLATE}" > "$1"
}

case "${1:-}" in
    validate) validate ;;
    materialize) shift; materialize "$@" ;;
    marketing-version) load_version; printf '%s\n' "${MARKETING_VERSION}" ;;
    build-number) load_version; printf '%s\n' "${BUILD_NUMBER}" ;;
    *) echo "Usage: $0 {validate|materialize OUTPUT_PATH|marketing-version|build-number}" >&2; exit 64 ;;
esac
