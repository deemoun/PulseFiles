#!/usr/bin/env bash
# Copyright (c) 2026 Dmitry Yarygin
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PULSEFILES_LICENSE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "${REPO_ROOT}"

copyright='Copyright (c) 2026 Dmitry Yarygin'
identifier='SPDX-License-Identifier: GPL-3.0-or-later'
fail=0

while IFS= read -r -d '' path; do
    if ! head -n 6 "${path}" | grep -Fq "${copyright}"; then
        echo "error: missing project copyright header: ${path}" >&2
        fail=1
    fi
    if ! head -n 6 "${path}" | grep -Fq "${identifier}"; then
        echo "error: missing GPL-3.0-or-later SPDX header: ${path}" >&2
        fail=1
    fi
done < <(find . \
    -path './.git' -prune -o \
    -path './.build' -prune -o \
    -path './artifacts' -prune -o \
    -type f \( -name '*.swift' -o -name '*.sh' \) -print0)

exit "${fail}"
