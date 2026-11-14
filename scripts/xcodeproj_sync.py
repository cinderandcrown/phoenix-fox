#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Keep PhoenixFox.xcodeproj in step with the Swift files on disk.

The project file is checked in so the build needs nothing but Xcode. This script is the
way to change it without a Mac: it adds every Swift file under OpenVision/ and
OpenVisionTests/ that the project does not list yet, and removes entries whose file is
gone. Run it from the repository root after adding, moving, or deleting a source file:

    python3 scripts/xcodeproj_sync.py            # apply
    python3 scripts/xcodeproj_sync.py --check    # exit 1 if the project is out of date

Object ids are derived from the file path, so the same change always produces the same
project file and two branches adding the same file do not conflict.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "PhoenixFox.xcodeproj" / "project.pbxproj"

# Source root on disk -> the target whose Sources phase compiles it.
TARGETS = {
    "OpenVision": "PhoenixFox",
    "OpenVisionTests": "PhoenixFoxTests",
}

# Listed in the project but not in the repository: copied from its .example before a build.
GENERATED = {"OpenVision/Config/Config.swift"}


def object_id(kind: str, path: str) -> str:
    return hashlib.sha1(f"{kind}:{path}".encode()).hexdigest()[:24].upper()


class Project:
    def __init__(self, text: str) -> None:
        self.text = text

    # --- reading -------------------------------------------------------------------

    def section(self, name: str) -> tuple[int, int]:
        start = self.text.index(f"/* Begin {name} section */")
        end = self.text.index(f"/* End {name} section */")
        return start, end

    def groups(self) -> dict[str, dict]:
        """Every PBXGroup: id -> {name, path, children ids, span}."""
        start, end = self.section("PBXGroup")
        pattern = re.compile(
            r"\t\t([0-9A-F]{24})(?: /\* (.*?) \*/)? = \{\n\t\t\tisa = PBXGroup;\n"
            r"\t\t\tchildren = \(\n(.*?)\t\t\t\);\n(.*?)\t\t\};\n",
            re.S,
        )
        found = {}
        for match in pattern.finditer(self.text, start, end):
            attributes = match.group(4)
            path = re.search(r"\tpath = (.*?);", attributes)
            found[match.group(1)] = {
                "name": match.group(2),
                "path": path.group(1).strip('"') if path else None,
                "children": re.findall(r"([0-9A-F]{24})", match.group(3)),
                "children_span": match.span(3),
            }
        return found

    def file_references(self) -> dict[str, str]:
        """id -> file name, for Swift sources."""
        start, end = self.section("PBXFileReference")
        pattern = re.compile(
            r"\t\t([0-9A-F]{24}) /\* .*? \*/ = \{isa = PBXFileReference;[^\n]*?"
            r"lastKnownFileType = sourcecode\.swift;[^\n]*? path = (.*?); sourceTree"
        )
        return {m.group(1): m.group(2).strip('"') for m in pattern.finditer(self.text, start, end)}

    def group_for(self, source_root: str) -> str:
        for identifier, group in self.groups().items():
            if group["path"] == source_root:
                return identifier
        raise SystemExit(f"No group with path {source_root} in the project.")

    def listed_files(self, source_root: str) -> dict[str, str]:
        """Relative path -> file reference id, for Swift files under one source root."""
        groups = self.groups()
        references = self.file_references()
        listed: dict[str, str] = {}

        def walk(identifier: str, prefix: str) -> None:
            for child in groups[identifier]["children"]:
                if child in groups:
                    walk(child, f"{prefix}/{groups[child]['path']}")
                elif child in references:
                    listed[f"{prefix}/{references[child]}"] = child

        walk(self.group_for(source_root), source_root)
        return listed

    def sources_phase(self, target: str) -> str:
        native = re.search(
            r"\t\t[0-9A-F]{24} /\* [^*]*? \*/ = \{\n\t\t\tisa = PBXNativeTarget;.*?buildPhases = \((.*?)\);"
            r".*?\t\t\tname = " + re.escape(target) + ";",
            self.text,
            re.S,
        )
        if not native:
            raise SystemExit(f"No target named {target} in the project.")
        phase = re.search(r"([0-9A-F]{24}) /\* Sources \*/", native.group(1))
        if not phase:
            raise SystemExit(f"Target {target} has no Sources phase.")
        return phase.group(1)

    # --- writing -------------------------------------------------------------------

    def insert_before_section_end(self, section: str, line: str) -> None:
        marker = f"/* End {section} section */"
        index = self.text.index(marker)
        self.text = self.text[:index] + line + self.text[index:]

    def append_child(self, group_id: str, child_id: str, comment: str) -> None:
        _, end = self.groups()[group_id]["children_span"]
        self.text = self.text[:end] + f"\t\t\t\t{child_id} /* {comment} */,\n" + self.text[end:]

    def ensure_group(self, parent_id: str, name: str, full_path: str) -> str:
        groups = self.groups()
        for child in groups[parent_id]["children"]:
            if child in groups and groups[child]["path"] == name:
                return child
        identifier = object_id("group", full_path)
        self.insert_before_section_end(
            "PBXGroup",
            f"\t\t{identifier} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n"
            f"\t\t\tpath = {name};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n",
        )
        self.append_child(parent_id, identifier, name)
        return identifier

    def add_file(self, relative: str, source_root: str, target: str) -> None:
        parts = relative.split("/")
        name = parts[-1]
        group_id = self.group_for(source_root)
        walked = source_root
        for folder in parts[1:-1]:
            walked = f"{walked}/{folder}"
            group_id = self.ensure_group(group_id, folder, walked)

        reference = object_id("file", relative)
        build_file = object_id("build", relative)
        self.insert_before_section_end(
            "PBXFileReference",
            f"\t\t{reference} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"path = {name}; sourceTree = \"<group>\"; }};\n",
        )
        self.insert_before_section_end(
            "PBXBuildFile",
            f"\t\t{build_file} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {reference} /* {name} */; }};\n",
        )
        self.append_child(group_id, reference, name)

        phase = self.sources_phase(target)
        files = re.search(
            r"\t\t" + phase + r" /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;.*?files = \(\n(.*?)\t\t\t\);",
            self.text,
            re.S,
        )
        end = files.end(1)
        self.text = self.text[:end] + f"\t\t\t\t{build_file} /* {name} in Sources */,\n" + self.text[end:]

    def remove_file(self, reference: str) -> None:
        build_files = re.findall(
            r"\t\t([0-9A-F]{24}) /\* [^\n]*? \*/ = \{isa = PBXBuildFile; fileRef = " + reference + r"[ ;]", self.text
        )
        for identifier in [reference, *build_files]:
            self.text = re.sub(r"[^\n]*\b" + identifier + r"\b[^\n]*\n", "", self.text)


def sync(check_only: bool) -> int:
    project = Project(PROJECT.read_text())
    added: list[str] = []
    removed: list[str] = []

    for source_root, target in TARGETS.items():
        on_disk = {
            path.relative_to(ROOT).as_posix()
            for path in (ROOT / source_root).rglob("*.swift")
        } | {path for path in GENERATED if path.startswith(f"{source_root}/")}
        listed = project.listed_files(source_root)
        for relative in sorted(on_disk - listed.keys()):
            added.append(relative)
            if not check_only:
                project.add_file(relative, source_root, target)
        for relative in sorted(listed.keys() - on_disk):
            removed.append(relative)
            if not check_only:
                project.remove_file(listed[relative])

    for relative in added:
        print(f"{'missing from project' if check_only else 'added'}: {relative}")
    for relative in removed:
        print(f"{'listed but not on disk' if check_only else 'removed'}: {relative}")

    if check_only:
        return 1 if added or removed else 0
    if added or removed:
        PROJECT.write_text(project.text)
    else:
        print("Project already lists every Swift source.")
    return 0


if __name__ == "__main__":
    sys.exit(sync(check_only="--check" in sys.argv[1:]))
