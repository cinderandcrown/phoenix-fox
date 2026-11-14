# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Tests for cost_model.py. Run with: python3 -m unittest discover -s scripts"""

import contextlib
import io
import os
import re
import tempfile
import unittest

import cost_model as model

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCUMENT = os.path.join(ROOT, "docs", "BUSINESS_MODEL.md")


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as file:
        return file.read()


def run(arguments):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = model.main(arguments)
    return code, out.getvalue(), err.getvalue()


class ImageTokens(unittest.TestCase):
    """Each rule against the examples its vendor publishes."""

    def test_anthropic_examples(self):
        self.assertEqual(model.image_tokens("anthropic", 1000, 1000), 1296)
        self.assertEqual(model.image_tokens("anthropic", 200, 200), 64)
        self.assertEqual(model.image_tokens("anthropic", 1092, 1092), 1521)

    def test_openai_patch_example(self):
        self.assertEqual(model.image_tokens("openai-patches", 1024, 1024), 1229)

    def test_openai_tile_example_is_six_tiles(self):
        self.assertEqual(model.image_tokens("openai-tiles", 2048, 4096), 2_833 + 6 * 5_667)

    def test_one_look_on_each_rule(self):
        size = (model.LOOK_WIDTH, model.LOOK_HEIGHT)
        self.assertEqual(model.image_tokens("anthropic", *size), 448)
        self.assertEqual(model.image_tokens("openai-patches", *size), 404)
        self.assertEqual(model.image_tokens("openai-tiles", *size), 14_167)
        self.assertEqual(model.image_tokens("xai", *size), 768)

    def test_a_look_stays_under_the_anthropic_limit(self):
        self.assertLess(model.image_tokens("anthropic", model.LOOK_WIDTH, model.LOOK_HEIGHT), 1_568)

    def test_an_unknown_rule_is_an_error(self):
        with self.assertRaises(ValueError):
            model.image_tokens("guess", 10, 10)


class Costs(unittest.TestCase):
    def test_a_question_worked_by_hand(self):
        # 1,500 tokens in at $0.10 a million and 120 out at $0.50 a million.
        self.assertAlmostEqual(model.question("gpt-6-luna"), 0.00021, places=9)
        # 1,500 in at $1.25 and 120 out at $2.50.
        self.assertAlmostEqual(model.question("grok-4.3"), 0.002175, places=9)

    def test_a_look_adds_only_the_photo(self):
        photo = 404 * 0.10 / 1_000_000
        self.assertAlmostEqual(model.look("gpt-6-luna") - model.question("gpt-6-luna"), photo, places=12)

    def test_all_hands_is_one_turn_for_each_assistant(self):
        self.assertAlmostEqual(model.bot_turn(), 0.0045, places=9)
        self.assertAlmostEqual(model.all_hands(), model.TEAM_SIZE * 0.0045, places=9)

    def test_a_held_long_poll_is_billed_for_every_second(self):
        waiting = 3_600 * 0.125 * 12.50 / 1_000_000
        self.assertAlmostEqual(model.relay_hour(), waiting + 20 * 0.45 / 1_000_000, places=12)

    def test_what_apple_leaves(self):
        self.assertAlmostEqual(model.net(9.99, 0.15), 8.4915)
        self.assertAlmostEqual(model.net(9.99, 0.30), 6.993)
        self.assertAlmostEqual(model.margin(10.00, 0.15, 4.25), 0.5)

    def test_a_plan_with_no_hosted_model_costs_nothing_to_serve(self):
        own = next(plan for plan in model.PLANS if plan.name == "Own AI")
        for usage in model.USAGE:
            self.assertEqual(model.hosted_month(own, usage), 0)
        self.assertEqual(model.cap_month(own), 0)

    def test_no_subscriber_can_cost_more_than_the_whole_allowance(self):
        for plan in model.PLANS:
            for usage in model.USAGE:
                self.assertLessEqual(model.hosted_month(plan, usage), model.cap_month(plan) + 1e-12)

    def test_the_proposed_plans_meet_the_margin_targets(self):
        self.assertEqual(model.targets_missed(), [])

    def test_a_plan_that_gives_too_much_away_is_caught(self):
        generous = model.Plan("Bot Team", 19.99, 159.99, 2_400, 600, 20_000)
        original = model.PLANS
        model.PLANS = (generous,)
        try:
            missed = model.targets_missed()
        finally:
            model.PLANS = original
        self.assertTrue(any("whole allowance" in line for line in missed), missed)

    def test_a_yearly_price_is_a_discount_not_a_markup(self):
        for plan in model.PLANS:
            self.assertLessEqual(plan.yearly, 12 * plan.monthly)

    def test_plans_cost_more_as_they_hold_more(self):
        prices = [plan.monthly for plan in model.PLANS]
        self.assertEqual(prices, sorted(prices))


class Writing(unittest.TestCase):
    def test_money(self):
        self.assertEqual(model.money(0), "$0")
        self.assertEqual(model.money(19.99), "$19.99")
        self.assertEqual(model.money(1234.5), "$1,234.50")
        self.assertEqual(model.money(0.018), "$0.018")
        self.assertEqual(model.money(0.00021), "$0.00021")
        self.assertEqual(model.money(0.0045), "$0.0045")
        self.assertEqual(model.money(0.08), "$0.08")

    def test_percent_never_rounds_a_cost_away(self):
        self.assertEqual(model.percent(0.84), "84%")
        self.assertEqual(model.percent(0.9954), "over 99%")
        self.assertEqual(model.percent(1.0), "100%")
        self.assertEqual(model.percent(0.994), "99%")

    def test_every_price_names_a_source(self):
        for priced in model.MODELS.values():
            self.assertIn(priced.source, model.SOURCES)
        for address in model.SOURCES.values():
            self.assertTrue(address.startswith("https://"), address)

    def test_rewrite_replaces_a_stale_table_and_leaves_the_words(self):
        stale = "Before.\n" + "\n".join(
            f"<!-- cost-model:{name} -->\nold\n<!-- /cost-model:{name} -->\nAfter {name}." for name in model.TABLES
        )
        fresh = model.rewrite(stale)
        self.assertNotIn("\nold\n", fresh)
        self.assertTrue(fresh.startswith("Before.\n"))
        for name in model.TABLES:
            self.assertIn(model.block(name), fresh)
            self.assertIn(f"After {name}.", fresh)
        self.assertEqual(model.rewrite(fresh), fresh)

    def test_rewrite_refuses_a_document_with_a_table_missing(self):
        with self.assertRaises(ValueError):
            model.rewrite("<!-- cost-model:prices -->\n<!-- /cost-model:prices -->")

    def test_check_fails_on_a_stale_document_and_write_repairs_it(self):
        stale = "\n".join(f"<!-- cost-model:{name} -->\n<!-- /cost-model:{name} -->" for name in model.TABLES)
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "doc.md")
            with open(path, "w", encoding="utf-8") as file:
                file.write(stale)
            code, _, err = run(["--check", path])
            self.assertEqual(code, 1)
            self.assertIn("out of date", err)
            self.assertEqual(run(["--write", path])[0], 0)
            self.assertEqual(run(["--check", path])[0], 0)

    def test_printing_the_tables_shows_every_one(self):
        code, out, _ = run([])
        self.assertEqual(code, 0)
        for name in model.TABLES:
            self.assertIn(f"## {name}", out)


class Repository(unittest.TestCase):
    """The model against the app it describes, so neither drifts from the other."""

    def test_the_document_holds_the_current_tables(self):
        document = read("docs", "BUSINESS_MODEL.md")
        self.assertEqual(model.rewrite(document), document, "Run: python3 scripts/cost_model.py --write docs/BUSINESS_MODEL.md")

    def test_the_document_gives_the_date_the_prices_were_read(self):
        self.assertIn(model.FETCHED, read("docs", "BUSINESS_MODEL.md"))

    def test_the_document_links_every_source(self):
        document = read("docs", "BUSINESS_MODEL.md")
        for address in model.SOURCES.values():
            self.assertIn(address, document)

    def test_the_plans_are_the_ones_the_app_names(self):
        swift = read("OpenVision", "Services", "Store", "Core", "Plan.swift")
        named = re.findall(r'case \.\w+: return "([^"]+)"', swift)
        self.assertEqual([plan.name for plan in model.PLANS], named)

    def test_the_fast_models_are_the_ones_the_app_asks_for(self):
        swift = read("OpenVision", "Services", "Brain", "BrainCatalog.swift")
        # xAI lists grok-4.20-non-reasoning at grok-4.3's price, and answers the retired
        # fallback name with grok-4.3 itself, so one row prices both.
        self.assertIn('static let defaultModel = "grok-4.20-non-reasoning"', read("OpenVision", "Services", "AIBackend", "GrokService.swift"))
        self.assertIn('static let grok = "grok-4-fast-non-reasoning"', swift)
        self.assertIn('static let claude = "claude-haiku-4-5"', swift)
        self.assertIn('static let openAI = "gpt-4o-mini"', swift)
        for name in ("grok-4.3", "claude-haiku-4-5", "gpt-4o-mini"):
            self.assertIn(name, model.MODELS)

    def test_a_look_is_the_size_the_app_sends(self):
        swift = read("OpenVision", "Services", "Brain", "ImageBudget.swift")
        self.assertIn("maxEdge: CGFloat = 768", swift)
        self.assertIn("format.scale = 1", swift)
        self.assertEqual(max(model.LOOK_WIDTH, model.LOOK_HEIGHT), 768)
        # A 720 by 1280 frame keeps its shape.
        self.assertEqual(model.LOOK_WIDTH * 1280, model.LOOK_HEIGHT * 720)

    def test_guide_mode_stops_asking_the_cloud_where_the_model_says(self):
        swift = read("OpenVision", "Services", "Accessibility", "GuideMode.swift")
        self.assertIn(f"modelCalls < {model.GUIDE_CHECKS_PER_SESSION}", swift)

    def test_the_relay_holds_a_wait_for_three_minutes(self):
        self.assertIn("reply_poll: 180", read("relay", "src", "handle.ts"))


if __name__ == "__main__":
    unittest.main()
