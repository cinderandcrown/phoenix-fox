#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Tests for xcodeproj_sync.py. Run with: python3 -m unittest discover -s scripts"""

import unittest

import xcodeproj_sync as sync


class QuotingTests(unittest.TestCase):
    def test_plain_names_stay_bare(self):
        for name in ["Home.swift", "Core", "a/b_c$1.swift"]:
            self.assertEqual(sync.quoted(name), name)

    def test_names_xcode_cannot_read_bare_are_quoted(self):
        self.assertEqual(sync.quoted("HapticCue+Play.swift"), '"HapticCue+Play.swift"')
        self.assertEqual(sync.quoted("Two Words.swift"), '"Two Words.swift"')
        self.assertEqual(sync.quoted("dash-ed.swift"), '"dash-ed.swift"')
        self.assertEqual(sync.quoted('say "hi".swift'), '"say \\"hi\\".swift"')
        self.assertEqual(sync.quoted(""), '""')

    def test_a_bare_plus_is_found_and_repaired(self):
        line = "\t\tAB /* A+B.swift */ = {isa = PBXFileReference; path = A+B.swift; sourceTree = \"<group>\"; };\n"
        self.assertEqual(sync.unreadable_values(line), ["A+B.swift"])
        repaired = sync.quote_unreadable_values(line)
        self.assertIn('path = "A+B.swift";', repaired)
        self.assertEqual(sync.unreadable_values(repaired), [])
        self.assertEqual(sync.quote_unreadable_values(repaired), repaired)

    def test_quoted_and_plain_values_are_left_alone(self):
        text = (
            "\t\t\tpath = Core;\n"
            "\t\t\tname = \"Phoenix Fox\";\n"
            "\t\t\tpath = \"A+B.swift\";\n"
            "\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        )
        self.assertEqual(sync.unreadable_values(text), [])
        self.assertEqual(sync.quote_unreadable_values(text), text)


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.project = sync.Project(sync.PROJECT.read_text())

    def test_the_checked_in_project_is_readable(self):
        self.assertEqual(sync.unreadable_values(self.project.text), [])

    def test_a_file_with_a_plus_is_added_quoted_and_read_back(self):
        relative = "OpenVision/Brand New/Thing+Extra.swift"
        self.project.add_file(relative, "OpenVision", "PhoenixFox")
        self.assertIn('path = "Thing+Extra.swift";', self.project.text)
        self.assertIn('path = "Brand New";', self.project.text)
        self.assertEqual(sync.unreadable_values(self.project.text), [])
        listed = self.project.listed_files("OpenVision")
        self.assertIn(relative, listed)
        compiled = self.project.compiled_references(self.project.sources_phase("PhoenixFox"))
        self.assertIn(listed[relative], compiled)

    def test_a_removed_file_leaves_no_trace(self):
        relative = "OpenVision/App/Thing+Extra.swift"
        before = self.project.text
        self.project.add_file(relative, "OpenVision", "PhoenixFox")
        self.project.remove_file(self.project.listed_files("OpenVision")[relative])
        self.assertEqual(self.project.text, before)


if __name__ == "__main__":
    unittest.main()
