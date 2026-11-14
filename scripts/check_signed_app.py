#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Check a signed Phoenix Fox app before it is uploaded.

A build can sign and upload without error and still be useless on a phone: the glasses
cannot register without the Meta values, the Meta AI app cannot return without the
associated domain, and push alerts need the production push service. This reads the app's
Info.plist and the entitlements in its signature and fails on any of those.

    check_signed_app.py --info Info.plist --entitlements entitlements.plist \\
        --team TEAMID --bundle-id com.example.app --version 1.0.0 --build 42.1 \\
        --owner-build yes

It prints which checks passed. It never prints the Meta client token.
"""

from __future__ import annotations

import argparse
import plistlib
import sys
from typing import Any

LINK_HOST = "phoenix-fox-links.cinderandcrown.workers.dev"


def is_on(value: Any) -> bool:
    """Whether a yes-or-no build setting is on. Mirrors InfoFlag in BuildFlavor.swift."""
    if isinstance(value, bool):
        return value
    return isinstance(value, str) and value.strip().lower() in ("yes", "true", "1")


def is_owner_build(info: dict[str, Any]) -> bool:
    """Whether the app will run as the owner's build. Mirrors BuildFlavor.swift."""
    return is_on(info.get("PhoenixFoxOwnerBuild"))


def store_setting(info: dict[str, Any]) -> bool:
    """Whether the build asks to sell plans. Mirrors StoreSwitch in StoreCatalog.swift."""
    return is_on(info.get("PhoenixFoxStoreEnabled"))


def problems(
    info: dict[str, Any],
    entitlements: dict[str, Any],
    team: str,
    bundle_id: str,
    version: str,
    build: str,
    owner_build: bool | None = None,
) -> list[str]:
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

    if owner_build is True:
        expect(is_owner_build(info), "This is not the owner's build. PHOENIX_FOX_OWNER_BUILD=YES did not reach Info.plist, so every feature would start off.")
        expect(not store_setting(info), "The owner's build asks to sell plans. PHOENIX_FOX_STORE must be NO in it. The app would still unlock everything, but the build is not the one that was meant.")
    elif owner_build is False:
        expect(not is_owner_build(info), "This is the owner's build, with every feature on and the beta glasses capabilities allowed. It must not go out as a standard build.")

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
    parser.add_argument("--owner-build", choices=("yes", "no"), help="Fail unless the app is (yes) or is not (no) the owner's build.")
    options = parser.parse_args(arguments)
    with open(options.info, "rb") as file:
        info = plistlib.load(file)
    with open(options.entitlements, "rb") as file:
        entitlements = plistlib.load(file)

    owner_build = None if options.owner_build is None else options.owner_build == "yes"
    found = problems(info, entitlements, options.team, options.bundle_id, options.version, options.build, owner_build)
    if found:
        print("The signed app is not ready to upload:")
        for problem in found:
            print(f"  - {problem}")
        return 1
    extra = sorted(key for key in entitlements if key.startswith("com.apple.developer.") and key != "com.apple.developer.team-identifier")
    print(f"Signed app is ready: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), production push, Meta values present.")
    print("Entitlements: " + ", ".join(extra))
    print("Owner build: every feature on." if is_owner_build(info) else "Standard build.")
    if store_setting(info) and not is_owner_build(info):
        print("Store: asked for. It sells plans once the app has a privacy policy address.")
    else:
        print("Store: off. Nothing is for sale and everything is unlocked.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
