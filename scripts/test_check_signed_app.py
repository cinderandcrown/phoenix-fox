# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Tests for check_signed_app.py. Run with: python3 -m unittest discover -s scripts"""

import contextlib
import io
import os
import plistlib
import tempfile
import unittest

import check_signed_app as check

TEAM = "TEAM123456"
BUNDLE = "com.example.app"


def good_info():
    return {
        "CFBundleIdentifier": BUNDLE,
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "42.1",
        "ITSAppUsesNonExemptEncryption": False,
        "UIBackgroundModes": ["audio", "remote-notification"],
        "MWDAT": {
            "AppLinkURLScheme": "https://phoenix-fox-links.cinderandcrown.workers.dev/dat",
            "MetaAppID": "1651172483404286",
            "TeamID": TEAM,
            "ClientToken": "secret-client-token",
        },
    }


def good_entitlements():
    return {
        "application-identifier": f"{TEAM}.{BUNDLE}",
        "com.apple.developer.team-identifier": TEAM,
        "aps-environment": "production",
        "com.apple.developer.associated-domains": ["applinks:phoenix-fox-links.cinderandcrown.workers.dev"],
        "com.apple.developer.kernel.increased-memory-limit": True,
        "get-task-allow": False,
    }


def run(info, entitlements):
    return check.problems(info, entitlements, TEAM, BUNDLE, "1.0.0", "42.1")


class SignedAppTests(unittest.TestCase):
    def test_a_good_app_has_no_problems(self):
        self.assertEqual(run(good_info(), good_entitlements()), [])

    def test_each_fault_is_found(self):
        cases = [
            ("info", lambda d: d.update(CFBundleVersion="15"), "Build is"),
            ("info", lambda d: d.update(CFBundleShortVersionString="2.14.0"), "Version is"),
            ("info", lambda d: d.update(CFBundleIdentifier="com.other.app"), "Bundle ID"),
            ("info", lambda d: d.pop("ITSAppUsesNonExemptEncryption"), "ITSAppUsesNonExemptEncryption"),
            ("info", lambda d: d["MWDAT"].update(ClientToken=""), "ClientToken"),
            ("info", lambda d: d["MWDAT"].update(ClientToken="$(META_CLIENT_TOKEN)"), "ClientToken"),
            ("info", lambda d: d["MWDAT"].update(AppLinkURLScheme="phoenixfox"), "AppLinkURLScheme"),
            ("info", lambda d: d["MWDAT"].update(TeamID=""), "TeamID"),
            ("info", lambda d: d["MWDAT"].pop("MetaAppID"), "MetaAppID"),
            ("info", lambda d: d.pop("MWDAT"), "ClientToken"),
            ("info", lambda d: d["UIBackgroundModes"].append("processing"), "BGTaskSchedulerPermittedIdentifiers"),
            ("entitlements", lambda d: d.update({"aps-environment": "development"}), "Push"),
            ("entitlements", lambda d: d.pop("aps-environment"), "Push"),
            ("entitlements", lambda d: d.pop("com.apple.developer.associated-domains"), "Associated domain"),
            ("entitlements", lambda d: d.update({"get-task-allow": True}), "development signature"),
            ("entitlements", lambda d: d.update({"application-identifier": f"OTHER.{BUNDLE}"}), "different app or team"),
            ("entitlements", lambda d: d.update({"com.apple.developer.team-identifier": "OTHER"}), "team is not"),
        ]
        for which, damage, expected in cases:
            info, entitlements = good_info(), good_entitlements()
            damage(info if which == "info" else entitlements)
            found = run(info, entitlements)
            self.assertTrue(any(expected in problem for problem in found), f"{expected!r} not in {found}")

    def test_processing_mode_with_identifiers_is_allowed(self):
        info = good_info()
        info["UIBackgroundModes"].append("processing")
        info["BGTaskSchedulerPermittedIdentifiers"] = ["com.example.app.refresh"]
        self.assertEqual(run(info, good_entitlements()), [])

    def test_the_command_never_prints_the_client_token(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = {}
            for name, content in (("info", good_info()), ("entitlements", good_entitlements())):
                paths[name] = os.path.join(folder, f"{name}.plist")
                with open(paths[name], "wb") as file:
                    plistlib.dump(content, file)
            for build, expected in (("42.1", 0), ("43.1", 1)):
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    status = check.main(["--info", paths["info"], "--entitlements", paths["entitlements"], "--team", TEAM, "--bundle-id", BUNDLE, "--version", "1.0.0", "--build", build])
                self.assertEqual(status, expected)
                self.assertNotIn("secret-client-token", output.getvalue())

    def test_the_repository_plist_passes_the_checks_it_can(self):
        # Build settings are not expanded in the source file, so only fixed values are compared.
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "OpenVision/Resources/Info.plist"), "rb") as file:
            info = plistlib.load(file)
        with open(os.path.join(root, "OpenVision/OpenVision.entitlements"), "rb") as file:
            entitlements = plistlib.load(file)
        found = run(info, entitlements)
        for fixed in ("ITSAppUsesNonExemptEncryption", "AppLinkURLScheme", "MetaAppID", "BGTaskSchedulerPermittedIdentifiers", "Associated domain"):
            self.assertFalse(any(fixed in problem for problem in found), f"{fixed}: {found}")


if __name__ == "__main__":
    unittest.main()
