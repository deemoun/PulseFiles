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
