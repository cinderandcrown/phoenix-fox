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
    """Standard (release-channel) binary: real MetaAppID + ClientToken."""
    return {
        "CFBundleIdentifier": BUNDLE,
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "42.1",
        "ITSAppUsesNonExemptEncryption": False,
        "UIBackgroundModes": ["audio", "bluetooth-central", "remote-notification"],
        "NSBluetoothAlwaysUsageDescription": "Connects to the glasses.",
        "NSLocalNetworkUsageDescription": "Joins the glasses' Wi-Fi for the camera.",
        "NSBonjourServices": ["_bonjour._tcp"],
        "MWDAT": {
            "AppLinkURLScheme": "https://phoenix-fox-links.cinderandcrown.workers.dev/dat",
            "MetaAppID": "1651172483404286",
            "TeamID": TEAM,
            "ClientToken": "secret-client-token",
        },
    }


def good_owner_info():
    """Owner / DAT Developer Mode binary: MetaAppID 0 + ClientToken 0."""
    info = good_info()
    info["PhoenixFoxOwnerBuild"] = "YES"
    info["PhoenixFoxStoreEnabled"] = "NO"
    info["MWDAT"] = {
        "AppLinkURLScheme": "https://phoenix-fox-links.cinderandcrown.workers.dev/dat",
        "MetaAppID": "0",
        "TeamID": TEAM,
        "ClientToken": "0",
    }
    return info


def good_entitlements():
    return {
        "application-identifier": f"{TEAM}.{BUNDLE}",
        "com.apple.developer.team-identifier": TEAM,
        "aps-environment": "production",
        "com.apple.developer.associated-domains": ["applinks:phoenix-fox-links.cinderandcrown.workers.dev"],
        "com.apple.developer.kernel.increased-memory-limit": True,
        "com.apple.developer.networking.HotspotConfiguration": True,
        "com.apple.developer.networking.wifi-info": True,
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
            ("info", lambda d: d["UIBackgroundModes"].remove("bluetooth-central"), "bluetooth-central"),
            ("info", lambda d: d.update(NSBluetoothAlwaysUsageDescription=" "), "NSBluetoothAlwaysUsageDescription"),
            ("info", lambda d: d.pop("NSLocalNetworkUsageDescription"), "NSLocalNetworkUsageDescription"),
            ("info", lambda d: d.update(NSLocalNetworkUsageDescription=""), "NSLocalNetworkUsageDescription"),
            ("info", lambda d: d.pop("NSBonjourServices"), "NSBonjourServices"),
            ("info", lambda d: d.update(NSBonjourServices=["_other._tcp"]), "NSBonjourServices"),
            ("entitlements", lambda d: d.pop("com.apple.developer.networking.HotspotConfiguration"), "Hotspot Configuration"),
            ("entitlements", lambda d: d.update({"com.apple.developer.networking.wifi-info": False}), "Access Wi-Fi Information"),
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

    def test_the_owner_build_flag_is_checked_only_when_asked(self):
        standard, owner = good_info(), good_owner_info()
        unset = good_info()
        unset["PhoenixFoxOwnerBuild"] = "$(PHOENIX_FOX_OWNER_BUILD)"

        def check_owner(info, expected):
            return check.problems(info, good_entitlements(), TEAM, BUNDLE, "1.0.0", "42.1", expected)

        for info in (standard, owner, unset):
            self.assertEqual(check_owner(info, None), [])
        self.assertEqual(check_owner(owner, True), [])
        self.assertTrue(any("not the owner's build" in problem for problem in check_owner(standard, True)))
        self.assertTrue(any("not the owner's build" in problem for problem in check_owner(unset, True)))
        self.assertEqual(check_owner(standard, False), [])
        self.assertEqual(check_owner(unset, False), [])
        self.assertTrue(any("must not go out as a standard build" in problem for problem in check_owner(owner, False)))
        # Owner with a real App ID is rejected when --owner-build yes.
        wrong = good_info()
        wrong["PhoenixFoxOwnerBuild"] = "YES"
        found = check_owner(wrong, True)
        self.assertTrue(any("MetaAppID 0" in problem for problem in found), found)

    def test_the_owner_build_flag_reads_the_way_the_app_reads_it(self):
        for value, expected in (("YES", True), (" yes\n", True), ("true", True), ("1", True), (True, True),
                                ("NO", False), ("", False), (False, False), (None, False), ("$(PHOENIX_FOX_OWNER_BUILD)", False)):
            self.assertEqual(check.is_owner_build({"PhoenixFoxOwnerBuild": value}), expected, repr(value))
        self.assertFalse(check.is_owner_build({}))

    def test_the_repository_plist_takes_the_owner_flag_from_the_build_setting(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "OpenVision/Resources/Info.plist"), "rb") as file:
            info = plistlib.load(file)
        self.assertEqual(info.get("PhoenixFoxOwnerBuild"), "$(PHOENIX_FOX_OWNER_BUILD)")
        with open(os.path.join(root, "project.yml"), encoding="utf-8") as file:
            self.assertIn('PHOENIX_FOX_OWNER_BUILD: "NO"', file.read())
        with open(os.path.join(root, "PhoenixFox.xcodeproj/project.pbxproj"), encoding="utf-8") as file:
            project = file.read()
        self.assertEqual(project.count("PHOENIX_FOX_OWNER_BUILD = NO;"), 2)
        self.assertNotIn("PHOENIX_FOX_OWNER_BUILD = YES", project)
        with open(os.path.join(root, ".github/workflows/testflight.yml"), encoding="utf-8") as file:
            workflow = file.read()
        self.assertIn("PHOENIX_FOX_OWNER_BUILD=YES", workflow)
        self.assertIn("--owner-build yes", workflow)
        self.assertIn("META_APP_ID = 0", workflow)
        self.assertIn("META_CLIENT_TOKEN = 0", workflow)

    def test_the_owner_build_must_not_ask_to_sell_plans(self):
        owner = good_owner_info()
        for off in ("NO", "", False, "$(PHOENIX_FOX_STORE)"):
            owner["PhoenixFoxStoreEnabled"] = off
            self.assertEqual(check.problems(owner, good_entitlements(), TEAM, BUNDLE, "1.0.0", "42.1", True), [], repr(off))
        owner.pop("PhoenixFoxStoreEnabled")
        self.assertEqual(check.problems(owner, good_entitlements(), TEAM, BUNDLE, "1.0.0", "42.1", True), [])
        for on in ("YES", "true", True):
            owner["PhoenixFoxStoreEnabled"] = on
            found = check.problems(owner, good_entitlements(), TEAM, BUNDLE, "1.0.0", "42.1", True)
            self.assertTrue(any("PHOENIX_FOX_STORE must be NO" in problem for problem in found), repr(on))

    def test_a_standard_build_may_ask_to_sell_plans(self):
        standard = good_info()
        standard["PhoenixFoxStoreEnabled"] = "YES"
        self.assertEqual(check.problems(standard, good_entitlements(), TEAM, BUNDLE, "1.0.0", "42.1", False), [])
        self.assertEqual(run(standard, good_entitlements()), [])

    def test_the_repository_leaves_the_store_off(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "OpenVision/Resources/Info.plist"), "rb") as file:
            info = plistlib.load(file)
        self.assertEqual(info.get("PhoenixFoxStoreEnabled"), "$(PHOENIX_FOX_STORE)")
        self.assertFalse(check.store_setting(info))
        with open(os.path.join(root, "project.yml"), encoding="utf-8") as file:
            self.assertIn('PHOENIX_FOX_STORE: "NO"', file.read())
        with open(os.path.join(root, "PhoenixFox.xcodeproj/project.pbxproj"), encoding="utf-8") as file:
            project = file.read()
        self.assertEqual(project.count("PHOENIX_FOX_STORE = NO;"), 2)
        self.assertNotIn("PHOENIX_FOX_STORE = YES", project)
        with open(os.path.join(root, ".github/workflows/testflight.yml"), encoding="utf-8") as file:
            workflow = file.read()
        self.assertIn("PHOENIX_FOX_STORE=NO", workflow)
        self.assertNotIn("PHOENIX_FOX_STORE=YES", workflow)

    def test_the_command_says_whether_the_store_is_on(self):
        with tempfile.TemporaryDirectory() as folder:
            entitlements = os.path.join(folder, "entitlements.plist")
            with open(entitlements, "wb") as file:
                plistlib.dump(good_entitlements(), file)
            for setting, expected in (("NO", "Store: off."), ("YES", "Store: asked for.")):
                info = good_info()
                info["PhoenixFoxStoreEnabled"] = setting
                path = os.path.join(folder, f"info-{setting}.plist")
                with open(path, "wb") as file:
                    plistlib.dump(info, file)
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    status = check.main(["--info", path, "--entitlements", entitlements, "--team", TEAM, "--bundle-id", BUNDLE, "--version", "1.0.0", "--build", "42.1"])
                self.assertEqual(status, 0)
                self.assertIn(expected, output.getvalue())

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
        # MetaAppID and ClientToken come from build settings ($(META_APP_ID) /
        # $(META_CLIENT_TOKEN)); they are expanded only in the signed app, so the
        # source plist is not checked for digits/token the way TestFlight is.
        for fixed in ("ITSAppUsesNonExemptEncryption", "AppLinkURLScheme", "BGTaskSchedulerPermittedIdentifiers", "Associated domain",
                      "bluetooth-central", "NSBluetoothAlwaysUsageDescription", "NSLocalNetworkUsageDescription", "NSBonjourServices",
                      "Hotspot Configuration", "Access Wi-Fi Information"):
            self.assertFalse(any(fixed in problem for problem in found), f"{fixed}: {found}")
        meta = info.get("MWDAT") or {}
        app_id = str(meta.get("MetaAppID", ""))
        self.assertTrue(
            app_id.isdigit() or app_id == "$(META_APP_ID)",
            f"MetaAppID should be digits or $(META_APP_ID), got {app_id!r}",
        )

    def test_the_workflow_turns_on_the_capability_for_each_wifi_entitlement(self):
        # An entitlement whose capability is off on the App ID is left out of the App
        # Store profile, and the export step then fails to sign.
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, ".github/workflows/testflight.yml"), encoding="utf-8") as file:
            workflow = file.read()
        for capability in ("HOT_SPOT", "ACCESS_WIFI_INFORMATION"):
            self.assertIn(capability, workflow)


if __name__ == "__main__":
    unittest.main()
