#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
for directory in PulseFiles/Utilities PulseFiles/Models PulseFiles/Services PulseFiles/Commands; do
  if rg -n '^import (AppKit|SwiftUI|QuickLook|QuickLookThumbnailing)$' "$directory" --glob '*.swift'; then
    echo "error: presentation framework imported below the AppKit layer: $directory" >&2
    fail=1
  fi
done

# Presentation emits mutation intent to service capabilities. It must never call
# FileManager mutation primitives directly.
mutation='FileManager(\.default)?\.(createDirectory|removeItem|moveItem|copyItem|trashItem|replaceItem)|fileManager\.(createDirectory|removeItem|moveItem|copyItem|trashItem|replaceItem)'
for directory in PulseFiles/App PulseFiles/FilePane PulseFiles/Sidebar PulseFiles/Settings PulseFiles/Terminal PulseFiles/Debug PulseFiles/PresentationSupport; do
  if rg -n "$mutation" "$directory" --glob '*.swift' --glob '!**/SettingsService.swift'; then
    echo "error: direct filesystem mutation in presentation directory: $directory" >&2
    fail=1
  fi
done

exit "$fail"
