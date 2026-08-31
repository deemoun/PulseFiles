#!/usr/bin/env bash
# Copyright (c) 2026 Dmitry Yarygin
# SPDX-License-Identifier: GPL-3.0-or-later

# Disposable regression coverage for policy-derived architecture validation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/PulseFilesArchitecture.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/license-root"
export PULSEFILES_LICENSE_ROOT="$FIXTURE/license-root"
BASE="$FIXTURE/base"
mkdir -p "$BASE/PulseFiles"/{App,AppCoordination,Utilities,Models,Services,Commands,PresentationSupport,Terminal,FilePane,Sidebar,Settings}
mkdir -p "$BASE"/{PulseFilesCoreTests,PulseFilesServicesTests,PulseFilesTests,PulseFilesAppKitUITests}
cp "$REPO_ROOT/Package.swift" "$BASE/Package.swift"

new_case() {
  local name="$1"
  local destination="$FIXTURE/$name"
  cp -R "$BASE" "$destination"
  printf '%s' "$destination"
}

run_validator() {
  PULSEFILES_ARCHITECTURE_ROOT="$1" "$SCRIPT_DIR/validate_architecture.sh" >/dev/null 2>&1
}

reject_source() {
  local name="$1" path="$2" snippet="$3" case_root
  case_root="$(new_case "$name")"
  mkdir -p "$(dirname "$case_root/$path")"
  printf '%s\n' "$snippet" > "$case_root/$path"
  if run_validator "$case_root"; then
    echo "ERROR: architecture fixture was accepted: $name" >&2
    exit 1
  fi
}

accept_source() {
  local name="$1" path="$2" snippet="$3" case_root
  case_root="$(new_case "$name")"
  mkdir -p "$(dirname "$case_root/$path")"
  printf '%s\n' "$snippet" > "$case_root/$path"
  if ! run_validator "$case_root"; then
    echo "ERROR: architecture fixture was rejected: $name" >&2
    exit 1
  fi
}

# Mutation matching is receiver-independent and multiline-safe.
reject_source multiline-mutation PulseFiles/App/Fixture.swift $'try alias.moveItem(\n    at: source,\n    to: destination\n)'
accept_source file-exists PulseFiles/App/Fixture.swift 'let exists = fm.fileExists(atPath: path)'
accept_source directory-read PulseFiles/App/Fixture.swift 'let children = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)'

# Imports are checked from policy for every target, including composition.
reject_source lateral-feature-import PulseFiles/FilePane/Fixture.swift 'import PulseFilesSidebar'
reject_source coordination-lateral-import PulseFiles/AppCoordination/Fixture.swift 'import PulseFilesPane'
reject_source reverse-lower-layer-import PulseFiles/Services/Fixture.swift 'import PulseFilesTerminal'
accept_source composition-import PulseFiles/App/Fixture.swift 'import PulseFilesTerminal'
accept_source coordination-workflow-import PulseFiles/AppCoordination/Fixture.swift 'import PulseFilesWorkflows'

# A newly declared resource owner is automatically protected without editing a
# constructor-name regex.
case_root="$(new_case new-service-constructor)"
printf '%s\n' 'package final class BrandNewService {}' > "$case_root/PulseFiles/Services/BrandNewService.swift"
printf '%s\n' 'let service = BrandNewService()' > "$case_root/PulseFiles/Sidebar/Fixture.swift"
if run_validator "$case_root"; then
  echo 'ERROR: newly introduced service constructor was accepted' >&2
  exit 1
fi

# Manifest paths and all direct internal dependencies are compared to policy.
case_root="$(new_case stale-target-path)"
sed -i 's|path: "PulseFiles/FilePane"|path: "PulseFiles/App"|' "$case_root/Package.swift"
if run_validator "$case_root"; then
  echo 'ERROR: stale target path was accepted' >&2
  exit 1
fi

case_root="$(new_case undeclared-manifest-dependency)"
sed -i 's/dependencies: \["PulseFilesUtilities"\], path: "PulseFiles\/Models"/dependencies: ["PulseFilesUtilities", "PulseFilesTerminal"], path: "PulseFiles\/Models"/' "$case_root/Package.swift"
if run_validator "$case_root"; then
  echo 'ERROR: undeclared manifest dependency was accepted' >&2
  exit 1
fi

case_root="$(new_case missing-manifest-dependency)"
sed -i 's/"PulseFilesWorkflows", //' "$case_root/Package.swift"
if run_validator "$case_root"; then
  echo 'ERROR: missing direct manifest dependency was accepted' >&2
  exit 1
fi

echo 'Architecture dependency regression tests passed'
