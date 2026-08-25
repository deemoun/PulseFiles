#!/usr/bin/env bash
# Disposable regression coverage for presentation dependency detection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/PulseFilesArchitecture.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/PulseFiles/App"

# The validator also checks the feature-target declarations. Keep a minimal
# manifest in the disposable repository so the focused source fixtures exercise
# the rule named by each assertion instead of failing for an unrelated missing
# manifest.
cat > "$FIXTURE/Package.swift" <<'EOF'
.target(name: "PulseFilesPane", path: "PulseFiles/FilePane")
.target(name: "PulseFilesSidebar", path: "PulseFiles/Sidebar")
.target(name: "PulseFilesSettings", path: "PulseFiles/Settings")
.target(name: "PulseFilesTerminal", path: "PulseFiles/Terminal")
EOF

assert_rejected() {
  local name="$1" snippet="$2" file="$FIXTURE/PulseFiles/App/Fixture.swift"
  printf '%s\n' "$snippet" > "$file"
  if PULSEFILES_ARCHITECTURE_ROOT="$FIXTURE" "$SCRIPT_DIR/validate_architecture.sh" >/dev/null 2>&1; then
    printf 'ERROR: mutation fixture was accepted: %s\n' "$name" >&2
    exit 1
  fi
}

assert_accepted() {
  local name="$1" snippet="$2" file="$FIXTURE/PulseFiles/App/Fixture.swift"
  printf '%s\n' "$snippet" > "$file"
  if ! PULSEFILES_ARCHITECTURE_ROOT="$FIXTURE" "$SCRIPT_DIR/validate_architecture.sh" >/dev/null 2>&1; then
    printf 'ERROR: read-only fixture was rejected: %s\n' "$name" >&2
    exit 1
  fi
}

assert_rejected create-directory 'try fm.createDirectory(at: url, withIntermediateDirectories: true)'
assert_rejected create-file 'manager.createFile(atPath: path, contents: nil)'
assert_rejected remove-item 'try storage.removeItem(at: url)'
assert_rejected copy-item 'try localManager.copyItem(at: source, to: destination)'
assert_rejected move-item $'try alias.moveItem(\n    at: source, to: destination)'
assert_rejected replace-item 'try worker.replaceItemAt(destination, withItemAt: source)'
assert_rejected replace-item-labelled 'try worker.replaceItem(at: destination, withItemAt: source)'
assert_rejected trash-item 'try arbitraryReceiver.trashItem(at: url, resultingItemURL: nil)'
assert_rejected symbolic-link 'try fm.createSymbolicLink(at: url, withDestinationURL: target)'
assert_rejected hard-link 'try fm.linkItem(at: source, to: destination)'
assert_rejected attributes 'try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)'
assert_rejected data-write 'try payload.write(to: url, options: .atomic)'
assert_rejected writable-handle 'let handle = try FileHandle(forWritingTo: url)'
assert_rejected updating-handle 'let handle = try FileHandle(forUpdating: url)'
assert_rejected descriptor-handle 'let handle = FileHandle(fileDescriptor: descriptor)'

assert_accepted file-exists 'let exists = fm.fileExists(atPath: path)'
assert_accepted attributes-read 'let values = try manager.attributesOfItem(atPath: path)'
assert_accepted directory-read 'let children = try arbitrary.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)'
assert_accepted readable-handle 'let handle = try FileHandle(forReadingFrom: url)'

# Target extraction is part of the boundary: a feature directory must not be
# silently folded back into the executable by a stale manifest edit.
cp "$FIXTURE/Package.swift" "$FIXTURE/Package.swift.valid"
sed 's|path: "PulseFiles/FilePane"|path: "PulseFiles/App"|' \
  "$FIXTURE/Package.swift.valid" > "$FIXTURE/Package.swift"
if PULSEFILES_ARCHITECTURE_ROOT="$FIXTURE" "$SCRIPT_DIR/validate_architecture.sh" >/dev/null 2>&1; then
  echo 'ERROR: stale feature target mapping was accepted' >&2
  exit 1
fi
mv "$FIXTURE/Package.swift.valid" "$FIXTURE/Package.swift"

# Concrete service selection belongs to PulseFiles/App, never a feature.
mkdir -p "$FIXTURE/PulseFiles/Terminal"
printf '%s\n' 'let process = PTYTerminalProcess()' > "$FIXTURE/PulseFiles/Terminal/Fixture.swift"
if PULSEFILES_ARCHITECTURE_ROOT="$FIXTURE" "$SCRIPT_DIR/validate_architecture.sh" >/dev/null 2>&1; then
  echo 'ERROR: feature concrete-process construction was accepted' >&2
  exit 1
fi
rm "$FIXTURE/PulseFiles/Terminal/Fixture.swift"

# Peer features communicate through events/protocols, not lateral imports.
mkdir -p "$FIXTURE/PulseFiles/FilePane"
printf '%s\n' 'import PulseFilesSidebar' > "$FIXTURE/PulseFiles/FilePane/Fixture.swift"
if PULSEFILES_ARCHITECTURE_ROOT="$FIXTURE" "$SCRIPT_DIR/validate_architecture.sh" >/dev/null 2>&1; then
  echo 'ERROR: lateral feature import was accepted' >&2
  exit 1
fi
rm "$FIXTURE/PulseFiles/FilePane/Fixture.swift"

# Foundation layers may not reverse the dependency graph into presentation.
mkdir -p "$FIXTURE/PulseFiles/Services"
printf '%s\n' 'import PulseFilesTerminal' > "$FIXTURE/PulseFiles/Services/Fixture.swift"
if PULSEFILES_ARCHITECTURE_ROOT="$FIXTURE" "$SCRIPT_DIR/validate_architecture.sh" >/dev/null 2>&1; then
  echo 'ERROR: reverse presentation dependency was accepted' >&2
  exit 1
fi
rm "$FIXTURE/PulseFiles/Services/Fixture.swift"

# The composition root is expressly where concrete wiring and feature imports
# are approved.
cat > "$FIXTURE/PulseFiles/App/Fixture.swift" <<'EOF'
import PulseFilesTerminal
let terminal = TerminalViewController(
    terminalService: terminalState,
    processFactory: { PTYTerminalProcess() },
    accessPolicy: accessPolicy,
    liquidGlassStyle: style
)
EOF
if ! PULSEFILES_ARCHITECTURE_ROOT="$FIXTURE" "$SCRIPT_DIR/validate_architecture.sh" >/dev/null 2>&1; then
  echo 'ERROR: approved composition-root wiring was rejected' >&2
  exit 1
fi

echo "Architecture dependency regression tests passed"
