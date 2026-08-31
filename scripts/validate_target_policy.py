#!/usr/bin/env python3
"""Validate Package.swift and Swift imports against architecture_policy.json."""

import json
import pathlib
import re
import sys


root = pathlib.Path(sys.argv[1]).resolve()
policy = json.loads(pathlib.Path(sys.argv[2]).read_text())
production = policy["productionTargets"]
expected = {**production, **policy.get("testTargets", {})}
manifest = (root / "Package.swift").read_text()
failed = False


def error(message: str) -> None:
    global failed
    print(f"error: {message}", file=sys.stderr)
    failed = True


def target_blocks(source: str):
    marker = re.compile(r"\.(?:executableTarget|testTarget|target)\s*\(")
    for match in marker.finditer(source):
        depth = 0
        in_string = False
        escaped = False
        for index in range(match.end() - 1, len(source)):
            char = source[index]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
            elif char == '"':
                in_string = True
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    yield source[match.start():index + 1]
                    break


actual = {}
for block in target_blocks(manifest):
    name_match = re.search(r"\bname\s*:\s*\"([^\"]+)\"", block)
    path_match = re.search(r"\bpath\s*:\s*\"([^\"]+)\"", block)
    if not name_match or not path_match:
        continue
    dependencies_match = re.search(r"\bdependencies\s*:\s*\[(.*?)\]", block, re.S)
    dependencies = re.findall(r'"(PulseFiles[^\"]*)"', dependencies_match.group(1)) if dependencies_match else []
    actual[name_match.group(1)] = {"path": path_match.group(1), "dependencies": dependencies}

for name, declaration in expected.items():
    if name not in actual:
        error(f"Package.swift is missing declared target {name}")
        continue
    if actual[name]["path"] != declaration["path"]:
        error(f"target {name} path is {actual[name]['path']!r}; policy requires {declaration['path']!r}")
    if not (root / declaration["path"]).is_dir():
        error(f"target {name} policy path does not exist: {declaration['path']}")
    got = set(actual[name]["dependencies"])
    wanted = set(declaration["dependencies"])
    for dependency in sorted(got - wanted):
        error(f"target {name} has undeclared internal dependency {dependency}")
    for dependency in sorted(wanted - got):
        error(f"target {name} is missing direct internal dependency {dependency}")

# Assign overlapping source paths to the most-specific target. Files left under
# the executable's broad path (App, Debug, Resources) belong to composition.
paths = sorted(((pathlib.PurePosixPath(value["path"]), name) for name, value in production.items()),
               key=lambda item: len(item[0].parts), reverse=True)
imports = re.compile(r"^\s*(?:@testable\s+)?import\s+(PulseFiles[A-Za-z0-9_]*)\b", re.M)
for swift_file in (root / "PulseFiles").rglob("*.swift"):
    relative = pathlib.PurePosixPath(swift_file.relative_to(root).as_posix())
    owner = next((name for path, name in paths if relative == path or path in relative.parents), None)
    if owner is None:
        error(f"no production target policy owns {relative}")
        continue
    allowed = set(production[owner]["dependencies"])
    for imported in imports.findall(swift_file.read_text()):
        if imported != owner and imported not in allowed:
            error(f"{relative}: {owner} may not import {imported}")

# Fail closed for resource-owner-looking concrete types declared by Services.
# A peer may construct its own declarations; cross-layer construction requires
# an exact path/type exception in policy.
services_path = root / production["PulseFilesServices"]["path"]
declaration = re.compile(r"\b(?:class|actor|struct)\s+([A-Za-z_][A-Za-z0-9_]*(?:Service|Repository|Policy|Process))\b")
resource_owners = set()
if services_path.is_dir():
    for source in services_path.rglob("*.swift"):
        resource_owners.update(declaration.findall(source.read_text()))
exceptions = set(policy["serviceConstructorExceptions"])
for target in policy["peerPresentationTargets"]:
    directory = root / production[target]["path"]
    if not directory.is_dir():
        continue
    for source in directory.rglob("*.swift"):
        text = source.read_text()
        relative = source.relative_to(root).as_posix()
        for type_name in sorted(resource_owners):
            if re.search(rf"\b{re.escape(type_name)}\s*\(", text, re.S) and f"{relative}:{type_name}" not in exceptions:
                error(f"{relative}: peer presentation constructs service resource owner {type_name}")

sys.exit(1 if failed else 0)
