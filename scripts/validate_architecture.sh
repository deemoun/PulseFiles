#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PULSEFILES_ARCHITECTURE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "$REPO_ROOT"

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

for directory in "${feature_directories[@]}"; do
  [[ -d "$directory" ]] || continue
  if rg -n -U "$concrete_dependency" "$directory" --glob '*.swift'; then
    echo "error: feature constructs a concrete service instead of receiving a capability: $directory" >&2
    fail=1
  fi
done

# Feature modules are peers. They communicate upward using model events or
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
