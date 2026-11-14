#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Check a signed Phoenix Fox app before it is uploaded.

A build can sign and upload without error and still be useless on a phone: the glasses
cannot register without the Meta values, the Meta AI app cannot return without the
associated domain, and push alerts need the production push service. This reads the app's
Info.plist and the entitlements in its signature and fails on any of those.

    check_signed_app.py --info Info.plist --entitlements entitlements.plist \\
        --team TEAMID --bundle-id com.example.app --version 1.0.0 --build 42.1

It prints which checks passed. It never prints the Meta client token.
"""

from __future__ import annotations

import argparse
import plistlib
import sys
from typing import Any

LINK_HOST = "phoenix-fox-links.cinderandcrown.workers.dev"


def problems(info: dict[str, Any], entitlements: dict[str, Any], team: str, bundle_id: str, version: str, build: str) -> list[str]:
    found: list[str] = []

    def expect(condition: bool, problem: str) -> None:
        if not condition:
            found.append(problem)

    expect(info.get("CFBundleIdentifier") == bundle_id, f"Bundle ID is {info.get('CFBundleIdentifier')!r}, expected {bundle_id!r}.")
    expect(info.get("CFBundleShortVersionString") == version, f"Version is {info.get('CFBundleShortVersionString')!r}, expected {version!r}.")
    expect(info.get("CFBundleVersion") == build, f"Build is {info.get('CFBundleVersion')!r}, expected {build!r}.")
    expect(info.get("ITSAppUsesNonExemptEncryption") is False, "ITSAppUsesNonExemptEncryption must be false, or every build waits for an export answer.")

    meta = info.get("MWDAT") or {}
    expect(meta.get("AppLinkURLScheme") == f"https://{LINK_HOST}/dat", "MWDAT AppLinkURLScheme is not the universal link registered with Meta.")
    expect(str(meta.get("MetaAppID", "")).isdigit(), "MWDAT MetaAppID is missing.")
    expect(meta.get("TeamID") == team, "MWDAT TeamID is not the signing team.")
    token = meta.get("ClientToken") or ""
    expect(bool(token) and "$(" not in token, "MWDAT ClientToken is empty. The META_CLIENT_TOKEN secret did not reach the build.")

    modes = info.get("UIBackgroundModes") or []
    if "processing" in modes:
        expect(bool(info.get("BGTaskSchedulerPermittedIdentifiers")), "Background mode 'processing' needs BGTaskSchedulerPermittedIdentifiers. Apple refuses the upload without it.")

    expect(entitlements.get("application-identifier") == f"{team}.{bundle_id}", "The signature is for a different app or team.")
    expect(entitlements.get("com.apple.developer.team-identifier") == team, "The signature's team is not the signing team.")
    expect(entitlements.get("aps-environment") == "production", "Push is not set to production. TestFlight builds would get no alerts.")
    expect(f"applinks:{LINK_HOST}" in (entitlements.get("com.apple.developer.associated-domains") or []), "Associated domain is missing. The Meta AI app could not return to Phoenix Fox.")
    expect(entitlements.get("get-task-allow") is not True, "This is a development signature. App Store Connect refuses it.")
    return found


def main(arguments: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in ("info", "entitlements", "team", "bundle-id", "version", "build"):
        parser.add_argument(f"--{name}", required=True)
    options = parser.parse_args(arguments)
    with open(options.info, "rb") as file:
        info = plistlib.load(file)
    with open(options.entitlements, "rb") as file:
        entitlements = plistlib.load(file)

    found = problems(info, entitlements, options.team, options.bundle_id, options.version, options.build)
    if found:
        print("The signed app is not ready to upload:")
        for problem in found:
            print(f"  - {problem}")
        return 1
    extra = sorted(key for key in entitlements if key.startswith("com.apple.developer.") and key != "com.apple.developer.team-identifier")
    print(f"Signed app is ready: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), production push, Meta values present.")
    print("Entitlements: " + ", ".join(extra))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
