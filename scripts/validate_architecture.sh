#!/usr/bin/env bash
# Copyright (c) 2026 Dmitry Yarygin
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PULSEFILES_ARCHITECTURE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "$REPO_ROOT"

PULSEFILES_LICENSE_ROOT="${PULSEFILES_LICENSE_ROOT:-${REPO_ROOT}}" "${SCRIPT_DIR}/validate_license_headers.sh"

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
  PulseFiles/FilePane
  PulseFiles/Sidebar
  PulseFiles/Settings
  PulseFiles/Terminal
  PulseFiles/Debug
  PulseFiles/PresentationSupport
)

# Presentation features may consume lower-layer protocols and values, but only
# PulseFiles/App is allowed to choose concrete resource-owning implementations.
# Keep this list to concrete production types (not capability protocols or value
# helpers) so adding a service requires an explicit architecture decision.
concrete_dependency='\b(FileSystemService|FileOperationService|SandboxFileAccessPolicy|SettingsRepository|BookmarkService|RecentLocationService|FolderAccessGrantService|PTYTerminalProcess|StagingCleanupService|ScratchFolderCleanupService)[[:space:]]*\('
feature_directories=(
  PulseFiles/FilePane
  PulseFiles/Sidebar
  PulseFiles/Settings
  PulseFiles/Terminal
  PulseFiles/Debug
)

# Keep package target boundaries explicit. Debug is intentionally absent because it
# remains an application-only adapter; see DOCUMENTATION.md.
feature_target_mappings=(
  "PulseFilesPresentationSupport:PulseFiles/PresentationSupport"
  "PulseFilesPane:PulseFiles/FilePane"
  "PulseFilesSidebar:PulseFiles/Sidebar"
  "PulseFilesSettings:PulseFiles/Settings"
  "PulseFilesTerminal:PulseFiles/Terminal"
)
for mapping in "${feature_target_mappings[@]}"; do
  target="${mapping%%:*}"
  path="${mapping#*:}"
  if ! rg -q "name: \"${target}\"" Package.swift || ! rg -q "path: \"${path}\"" Package.swift; then
    echo "error: missing or stale SwiftPM feature target mapping: $target -> $path" >&2
    fail=1
  fi
done

# PresentationSupport exposes AppKit adapters for model, service, and workflow
# types. Keep those direct dependencies declared so isolated target builds do not
# lose types such as FileIconKey, FileSystemProbeAnswer, or MainCommand.
presentation_support_dependencies=(
  PulseFilesWorkflows
  PulseFilesServices
  PulseFilesModels
  PulseFilesUtilities
)
presentation_support_target="$({
  sed -n '/name: "PulseFilesPresentationSupport"/,/path: "PulseFiles\/PresentationSupport"/p' Package.swift
} || true)"
for dependency in "${presentation_support_dependencies[@]}"; do
  if ! printf '%s\n' "$presentation_support_target" | rg -q "dependencies:.*\"${dependency}\""; then
    echo "error: PulseFilesPresentationSupport is missing direct dependency: $dependency" >&2
    fail=1
  fi
done

for directory in "${feature_directories[@]}"; do
  [[ -d "$directory" ]] || continue
  if rg -n -U "$concrete_dependency" "$directory" --glob '*.swift'; then
    echo "error: feature constructs a concrete service instead of receiving a capability: $directory" >&2
    fail=1
  fi
done

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

# SwiftPM feature targets are peers. Their source-directory mapping is kept here
# in sync with Package.swift so imports cannot create undeclared lateral edges.
# Feature modules communicate upward using model events or
# small protocols; they must never import one another. The allowlist is an
# exact path/import pair and is intentionally empty today. Additions require an
# audited explanation beside the entry rather than a directory wildcard.
lateral_feature_modules='PulseFiles(Pane|Sidebar|Settings|Terminal|Debug)'
lateral_import_allowlist=()
for directory in "${feature_directories[@]}"; do
  [[ -d "$directory" ]] || continue
  while IFS= read -r finding; do
    [[ -z "$finding" ]] && continue
    relative_path="${finding%%:*}"
    imported_module="$(printf '%s' "$finding" | sed -E 's/^[^:]+:[0-9]+:import //')"
    allowed=0
    for entry in "${lateral_import_allowlist[@]}"; do
      [[ "$entry" == "$relative_path:$imported_module" ]] && allowed=1
    done
    if (( ! allowed )); then
      echo "error: unaudited lateral presentation dependency: $relative_path imports $imported_module" >&2
      fail=1
    fi
  done < <(rg -n "^import ${lateral_feature_modules}$" "$directory" --glob '*.swift' || true)
done

# Lower layers cannot point back at presentation, even if somebody edits the
# manifest to make such a reverse edge compile.
for directory in PulseFiles/Utilities PulseFiles/Models PulseFiles/Services PulseFiles/Commands; do
  [[ -d "$directory" ]] || continue
  if rg -n '^import PulseFiles(PresentationSupport|Pane|Sidebar|Settings|Terminal|Debug|App)$' "$directory" --glob '*.swift'; then
    echo "error: reverse dependency from lower layer to presentation: $directory" >&2
    fail=1
  fi
done

# Keep exceptions exact and auditable. Never add directory or basename globs.
# Persistence and the PTY descriptor adapter live in Services, so presentation
# currently needs no mutation exception.
presentation_mutation_allowlist=()

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
