#!/usr/bin/env bash
# Copyright (c) 2026 Dmitry Yarygin
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PULSEFILES_ARCHITECTURE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "$REPO_ROOT"

PULSEFILES_LICENSE_ROOT="${PULSEFILES_LICENSE_ROOT:-${REPO_ROOT}}" "${SCRIPT_DIR}/validate_license_headers.sh"

python3 "${SCRIPT_DIR}/validate_target_policy.py" "$REPO_ROOT" "${SCRIPT_DIR}/architecture_policy.json"

fail=0
for directory in PulseFiles/Utilities PulseFiles/Models PulseFiles/Services PulseFiles/Commands; do
  [[ -d "$directory" ]] || continue
  if rg -n '^import (AppKit|SwiftUI|QuickLook|QuickLookThumbnailing)$' "$directory" --glob '*.swift'; then
    echo "error: presentation framework imported below the AppKit layer: $directory" >&2
    fail=1
  fi
done

# Match mutation API call shapes rather than spelling particular receivers.
# This catches FileManager.default, injected properties, locals such as `fm`,
# and optional/chained aliases. `-U` also prevents line wrapping from evading a
# rule. Calls whose spelling is inherently ambiguous (Data/String writes and
# descriptor handles) are deliberately forbidden throughout presentation.
mutation='\.(createDirectory[[:space:]]*\([[:space:]]*(at|atPath):|createFile[[:space:]]*\([[:space:]]*atPath:|removeItem[[:space:]]*\([[:space:]]*at:|copyItem[[:space:]]*\([[:space:]]*at:|moveItem[[:space:]]*\([[:space:]]*at:|replaceItem(At)?[[:space:]]*\([[:space:]]*at:|replaceItemAt[[:space:]]*\(|trashItem[[:space:]]*\([[:space:]]*at:|createSymbolicLink[[:space:]]*\([[:space:]]*(at|atPath):|linkItem[[:space:]]*\([[:space:]]*(at|atPath):|setAttributes[[:space:]]*\(|write[[:space:]]*\([[:space:]]*to:)|FileHandle[[:space:]]*\([[:space:]]*(forWritingTo|forUpdating|fileDescriptor):'

presentation_directories=(
  PulseFiles/App
  PulseFiles/AppCoordination
  PulseFiles/FilePane
  PulseFiles/Sidebar
  PulseFiles/Settings
  PulseFiles/Terminal
  PulseFiles/Debug
  PulseFiles/PresentationSupport
)

# Read-only existence/resource probes can block on network and removable volumes.
# Presentation must use FileSystemProbing; composition-root folder location calls
# (`homeDirectoryForCurrentUser` and `urls(for:in:)`) are deliberately not matched.
presentation_probe='\.fileExists[[:space:]]*\(|\.resourceValues[[:space:]]*\(|\.getResourceValue[[:space:]]*\(|\.checkResourceIsReachable[[:space:]]*\('
presentation_probe_legacy_exceptions=(
  PulseFiles/App/Coordinators/FileCreationWorkflowCoordinator.swift
  PulseFiles/App/Coordinators/SearchWorkflowCoordinator.swift
  PulseFiles/App/Coordinators/NavigationPresentationCoordinators.swift
  PulseFiles/App/OpenFileCoordinator.swift
  PulseFiles/App/OpenEventRouter.swift
  PulseFiles/FilePane/FilePaneViewModel.swift
  PulseFiles/FilePane/FilePaneDropCoordinator.swift
  PulseFiles/PresentationSupport/Services/VolumeDiscoveryService.swift
)
for directory in "${presentation_directories[@]}"; do
  [[ -d "$directory" ]] || continue
  probe_arguments=(-n -U "$presentation_probe" "$directory" --glob '*.swift')
  for path in "${presentation_probe_legacy_exceptions[@]}"; do
    probe_arguments+=(--glob "!/$path")
  done
  if rg "${probe_arguments[@]}"; then
    echo "error: direct filesystem existence/resource probe in presentation directory: $directory" >&2
    fail=1
  fi
done

feature_directories=(
  PulseFiles/AppCoordination
  PulseFiles/FilePane
  PulseFiles/Sidebar
  PulseFiles/Settings
  PulseFiles/Terminal
  PulseFiles/Debug
)

# Feature modules must depend on authorization capabilities, never retain or accept
# the concrete production policy. Construction is checked separately above.
concrete_policy_dependency='(private|package|internal|public)?[[:space:]]*(let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*SandboxFileAccessPolicy|init[[:space:]]*\([^)]*SandboxFileAccessPolicy'
for directory in "${feature_directories[@]}"; do
  if rg -n -U "$concrete_policy_dependency" "$directory" --glob '*.swift'; then
    echo "error: feature stores or accepts concrete SandboxFileAccessPolicy: $directory" >&2
    fail=1
  fi
done

# Main-window workflow code receives resource-owning services from
# MainWindowDependencies. Concrete production assembly belongs in the
# composition root, not in the view controller or its focused coordinators.
window_workflow_construction='FolderAccessGrantService\.shared|\b(FileSystemService|FileOperationService|StagingCleanupService|ScratchFolderCleanupService)[[:space:]]*\('
if rg -n -U "$window_workflow_construction" \
    PulseFiles/App/MainWindowViewController.swift PulseFiles/App/Coordinators --glob '*.swift'; then
  echo "error: main-window workflow constructs a concrete service instead of using injected capabilities" >&2
  fail=1
fi

# Keep exceptions exact and auditable. Never add directory or basename globs.
# Persistence and the PTY descriptor adapter live in Services, so presentation
# currently needs no mutation exception.
mapfile -t presentation_mutation_allowlist < <(
  python3 -c 'import json,sys; [print(item) for item in json.load(open(sys.argv[1]))["presentationMutationExceptions"]]' \
    "${SCRIPT_DIR}/architecture_policy.json"
)

for directory in "${presentation_directories[@]}"; do
  [[ -d "$directory" ]] || continue
  rg_arguments=(-n -U "$mutation" "$directory" --glob '*.swift')
  for path in "${presentation_mutation_allowlist[@]}"; do
    rg_arguments+=(--glob "!/$path")
  done
  if rg "${rg_arguments[@]}"; then
    echo "error: direct filesystem mutation in presentation directory: $directory" >&2
    fail=1
  fi
done

exit "$fail"
