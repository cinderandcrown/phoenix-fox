#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""The numbers behind docs/BUSINESS_MODEL.md.

Every price here was read from the vendor's own page on the date in FETCHED and carries the
address it came from. Everything else is an assumption, and is named as one: how many tokens
a turn uses, how often somebody asks, what the plans cost. Change a number here, run
`--write`, and the tables in the document follow.

    cost_model.py                 print the tables
    cost_model.py --write DOC     rewrite the tables inside DOC
    cost_model.py --check DOC     fail if DOC's tables are out of date

Nothing here has been measured against a real bill. The app has not run on a phone yet.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass

FETCHED = "14 November 2026"

SOURCES = {
    "xai": "https://docs.x.ai/docs/models",
    "xai-retired": "https://docs.x.ai/developers/migration/may-15-retirement",
    "openai": "https://platform.openai.com/docs/pricing",
    "openai-images": "https://platform.openai.com/docs/guides/images-vision",
    "anthropic": "https://docs.anthropic.com/en/docs/about-claude/pricing",
    "anthropic-images": "https://docs.anthropic.com/en/docs/build-with-claude/vision",
    "google": "https://ai.google.dev/gemini-api/docs/pricing",
    "cloudflare": "https://developers.cloudflare.com/workers/platform/pricing/",
    "apple-small-business": "https://developer.apple.com/app-store/small-business-program/",
    "apple-subscriptions": "https://developer.apple.com/app-store/subscriptions/",
    "apple-membership": "https://developer.apple.com/programs/whats-included/",
}


# --- Prices read from the vendors -------------------------------------------------------


@dataclass(frozen=True)
class Model:
    name: str
    input: float  # dollars per million input tokens
    output: float  # dollars per million output tokens
    source: str
    image_rule: str
    used_for: str


MODELS = {
    model.name: model
    for model in (
        # The app's default for Grok is grok-4.20-non-reasoning, which xAI lists at this
        # price. Its fallback, grok-4-fast-non-reasoning, was retired on 15 May 2026 and is
        # answered by grok-4.3, also at this price.
        Model("grok-4.3", 1.25, 2.50, "xai", "xai", "Grok's default in the app (`grok-4.20-non-reasoning`, the same price), and an assistant's turn"),
        Model("claude-haiku-4-5", 1.00, 5.00, "anthropic", "anthropic", "Claude's default in the app"),
        Model("gpt-4o-mini", 0.15, 0.60, "openai", "openai-tiles", "OpenAI's default in the app"),
        Model("gpt-6-luna", 0.10, 0.50, "openai", "openai-patches", "Cheapest route found"),
        Model("claude-haiku-5.5", 0.10, 0.50, "anthropic", "anthropic", "Cheapest route found"),
    )
}

# Live voice, in dollars per minute, where the vendor publishes a price per minute. The app
# asks for Gemini 2.5 Flash native audio, which is priced by the token; the document says
# how the two compare.
GEMINI_LIVE_AUDIO_IN = 0.005
GEMINI_LIVE_VIDEO_IN = 0.002
GEMINI_LIVE_AUDIO_OUT = 0.018
XAI_VOICE = 0.08

# Cloudflare, for a hosted relay. A Durable Object is billed for 128 MB for as long as it
# cannot hibernate. A request that is waiting for a reply keeps it awake. A WebSocket that
# uses the hibernation API does not.
WORKERS_PAID_MONTHLY = 5.00
DURABLE_OBJECT_GB = 0.125
DURABLE_OBJECT_GB_SECOND = 12.50 / 1_000_000
WORKER_REQUEST = 0.30 / 1_000_000
DURABLE_OBJECT_REQUEST = 0.15 / 1_000_000

# Apple.
SMALL_BUSINESS_COMMISSION = 0.15
STANDARD_COMMISSION = 0.30
DEVELOPER_PROGRAM_YEARLY = 99.00


# --- Assumptions ------------------------------------------------------------------------

# One spoken question: the system prompt, the tool list, up to eight earlier messages
# (ConversationContext keeps eight), and the sentence. The reply is capped at 400 tokens in
# CloudChat and the persona asks for one to three short sentences.
TEXT_INPUT_TOKENS = 1_500
TEXT_OUTPUT_TOKENS = 120

# One look: a 720 by 1280 frame from the glasses, shrunk to 768 on the long edge by ImageBudget.
LOOK_WIDTH = 432
LOOK_HEIGHT = 768

# A turn handled by one of the owner's kind of assistant, if Cinder & Crown ran it for a
# subscriber. An assistant carries its own instructions, memory, and tools.
BOT_INPUT_TOKENS = 3_000
BOT_OUTPUT_TOKENS = 300
BOT_MODEL = "grok-4.3"
TEAM_SIZE = 4

HOSTED_MODEL = "gpt-6-luna"
DAYS = 30

# A hosted relay that holds its waits on hibernating WebSockets is awake only while it
# handles a message: about four requests and two seconds for one assistant turn.
RELAY_REQUESTS_PER_TURN = 4
RELAY_SECONDS_PER_TURN = 2

# How much of a live conversation the model spends talking.
LIVE_TALK_SHARE = 0.3

# Not an assumption: Guide mode asks a cloud model about hazards at most this many times in
# a session, and only with the wearer's own xAI key. GuideMode.swift holds the limit.
GUIDE_CHECKS_PER_SESSION = 60


@dataclass(frozen=True)
class Usage:
    name: str
    questions_per_day: int
    looks_per_day: int
    bot_tasks_per_day: int
    all_hands_per_day: int


USAGE = (
    Usage("Light", 5, 1, 3, 0),
    Usage("Typical", 20, 5, 15, 1),
    Usage("Heavy", 60, 20, 40, 2),
)


@dataclass(frozen=True)
class Plan:
    name: str
    monthly: float
    yearly: float
    questions: int  # hosted questions a month, 0 when the plan has no hosted model
    looks: int
    bot_turns: int


# Proposed prices and allowances. They are decisions to make, not market research.
PLANS = (
    Plan("Free", 0, 0, 0, 0, 0),
    Plan("Own AI", 2.99, 24.99, 0, 0, 0),
    Plan("Included AI", 9.99, 79.99, 2_400, 600, 0),
    Plan("Bot Team", 19.99, 159.99, 2_400, 600, 1_000),
)

# What the allowances have to leave, for a subscriber who uses every bit of them.
TARGET_AT_CAP_MONTHLY = 0.60
TARGET_AT_CAP_YEARLY = 0.40
TARGET_TYPICAL = 0.80

# A free described scene for someone with no key and no on-device model, if the hosted
# route is ever switched on for the free plan.
FREE_DESCRIPTIONS_PER_DAY = 10


# --- Image tokens -----------------------------------------------------------------------


def image_tokens(rule: str, width: int, height: int) -> int:
    """Input tokens one image costs, by each vendor's published rule."""
    if rule == "anthropic":
        # 28-pixel patches. Standard models stop at 1,568 patches, which this size is under.
        return math.ceil(width / 28) * math.ceil(height / 28)
    if rule == "openai-patches":
        # 32-pixel patches times the model's multiplier of 1.2.
        return math.ceil(math.ceil(width / 32) * math.ceil(height / 32) * 1.2)
    if rule == "openai-tiles":
        # gpt-4o-mini: 2,833 tokens, plus 5,667 for each 512-pixel tile.
        short, long = sorted((width, height))
        if long > 2048:
            short, long = short * 2048 // long, 2048
        if short > 768:
            short, long = 768, long * 768 // short
        return 2_833 + 5_667 * math.ceil(short / 512) * math.ceil(long / 512)
    if rule == "xai":
        # An assumption. xAI's page no longer gives a rule. Its earlier one was 256 tokens
        # for each 448-pixel tile plus one more tile, and that is used here.
        return 256 * (math.ceil(width / 448) * math.ceil(height / 448) + 1)
    raise ValueError(f"No image rule called {rule}")


# --- Costs ------------------------------------------------------------------------------


def turn(model: str, input_tokens: int, output_tokens: int, images: int = 0) -> float:
    """Dollars for one request."""
    priced = MODELS[model]
    seen = images * image_tokens(priced.image_rule, LOOK_WIDTH, LOOK_HEIGHT)
    return ((input_tokens + seen) * priced.input + output_tokens * priced.output) / 1_000_000


def question(model: str) -> float:
    return turn(model, TEXT_INPUT_TOKENS, TEXT_OUTPUT_TOKENS)


def look(model: str) -> float:
    return turn(model, TEXT_INPUT_TOKENS, TEXT_OUTPUT_TOKENS, images=1)


def bot_turn() -> float:
    return turn(BOT_MODEL, BOT_INPUT_TOKENS, BOT_OUTPUT_TOKENS)


def all_hands() -> float:
    return TEAM_SIZE * bot_turn()


def relay_hour() -> float:
    """Dollars for one hour of one long poll held open on a hosted relay, as the relay is built today."""
    waiting = 3_600 * DURABLE_OBJECT_GB * DURABLE_OBJECT_GB_SECOND
    polls = 3_600 / 180
    return waiting + polls * (WORKER_REQUEST + DURABLE_OBJECT_REQUEST)


def relay_turn() -> float:
    """Dollars for one assistant turn through a hosted relay that hibernates between messages."""
    awake = RELAY_SECONDS_PER_TURN * DURABLE_OBJECT_GB * DURABLE_OBJECT_GB_SECOND
    return awake + RELAY_REQUESTS_PER_TURN * (WORKER_REQUEST + DURABLE_OBJECT_REQUEST)


def hosted_bot_turn() -> float:
    return bot_turn() + relay_turn()


def live_minute() -> float:
    return GEMINI_LIVE_AUDIO_IN + GEMINI_LIVE_VIDEO_IN + LIVE_TALK_SHARE * GEMINI_LIVE_AUDIO_OUT


def own_key_month(usage: Usage, model: str) -> float:
    """What a person with their own key pays the model vendor in a month."""
    return DAYS * (usage.questions_per_day * question(model) + usage.looks_per_day * look(model))


def hosted_month(plan: Plan, usage: Usage) -> float:
    """What a subscriber costs Cinder & Crown in a month, held to the plan's allowances."""
    if plan.questions == 0:
        return 0.0
    questions = min(plan.questions, DAYS * usage.questions_per_day)
    looks = min(plan.looks, DAYS * usage.looks_per_day)
    cost = questions * question(HOSTED_MODEL) + looks * look(HOSTED_MODEL)
    if plan.bot_turns:
        asked = DAYS * (usage.bot_tasks_per_day + TEAM_SIZE * usage.all_hands_per_day)
        cost += min(plan.bot_turns, asked) * hosted_bot_turn()
    return cost


def cap_month(plan: Plan) -> float:
    """The most a subscriber can cost: every allowance used."""
    if plan.questions == 0:
        return 0.0
    cost = plan.questions * question(HOSTED_MODEL) + plan.looks * look(HOSTED_MODEL)
    return cost + plan.bot_turns * hosted_bot_turn()


def net(price: float, commission: float) -> float:
    return price * (1 - commission)


def margin(price: float, commission: float, cost: float) -> float:
    kept = net(price, commission)
    return (kept - cost) / kept


def fixed_yearly() -> float:
    return DEVELOPER_PROGRAM_YEARLY + 12 * WORKERS_PAID_MONTHLY


def subscribers_to_cover_fixed(plan: Plan, usage: Usage) -> int:
    each = 12 * (net(plan.monthly, SMALL_BUSINESS_COMMISSION) - hosted_month(plan, usage))
    return math.ceil(fixed_yearly() / each)


def free_descriptions_month() -> float:
    return DAYS * FREE_DESCRIPTIONS_PER_DAY * look(HOSTED_MODEL)


def targets_missed() -> list[str]:
    """Plans whose allowances no longer leave the margin the document promises."""
    typical = next(usage for usage in USAGE if usage.name == "Typical")
    missed = []
    for plan in PLANS:
        if plan.monthly == 0:
            continue
        checks = (
            ("monthly, whole allowance", margin(plan.monthly, SMALL_BUSINESS_COMMISSION, cap_month(plan)), TARGET_AT_CAP_MONTHLY),
            ("yearly, whole allowance", margin(plan.yearly / 12, SMALL_BUSINESS_COMMISSION, cap_month(plan)), TARGET_AT_CAP_YEARLY),
            ("monthly, typical use", margin(plan.monthly, SMALL_BUSINESS_COMMISSION, hosted_month(plan, typical)), TARGET_TYPICAL),
            ("monthly, whole allowance, 30% commission", margin(plan.monthly, STANDARD_COMMISSION, cap_month(plan)), 0.0),
        )
        for label, got, wanted in checks:
            if got < wanted:
                missed.append(f"{plan.name} ({label}): {got:.0%}, wanted at least {wanted:.0%}")
    return missed


# --- Tables -----------------------------------------------------------------------------


def money(amount: float) -> str:
    """Two decimals from ten cents up, two significant figures below that."""
    if amount == 0:
        return "$0"
    if amount >= 0.1:
        return f"${amount:,.2f}"
    places = 1 - math.floor(math.log10(amount))
    text = f"{amount:.{places}f}"
    while text.endswith("0") and len(text.split(".")[1]) > 2:
        text = text[:-1]
    return f"${text}"


def percent(share: float) -> str:
    """A whole percent. A share just under the whole is never rounded up to 100%."""
    if 0.995 <= share < 1:
        return "over 99%"
    return f"{share * 100:.0f}%"


def table(header: list[str], rows: list[list[str]]) -> str:
    lines = ["| " + " | ".join(header) + " |", "| " + " | ".join("---" for _ in header) + " |"]
    lines += ["| " + " | ".join(row) + " |" for row in rows]
    return "\n".join(lines)


def prices_table() -> str:
    rows = [
        [f"`{model.name}`", f"${model.input:.2f}", f"${model.output:.2f}", model.used_for, f"[{model.source}]({SOURCES[model.source]})"]
        for model in MODELS.values()
    ]
    return table(["Model", "Input, per million tokens", "Output, per million tokens", "Used for", "Source"], rows)


def per_use_table() -> str:
    rows = []
    for model in MODELS.values():
        seen = image_tokens(model.image_rule, LOOK_WIDTH, LOOK_HEIGHT)
        rows.append([f"`{model.name}`", money(question(model.name)), f"{seen:,}", money(look(model.name))])
    return table(["Model", "One spoken question", "Tokens for one photo", "One look"], rows)


def features_table() -> str:
    cheap, grok = HOSTED_MODEL, BOT_MODEL
    rows = [
        ["Wake word, hearing the sentence, speaking the reply", "On the phone", "Nobody", "$0"],
        ["Reading, money, colors, labels, Guide mode callouts, captions, sound alerts, task steps", "On the phone", "Nobody", "$0"],
        ["A question to the on-device model", "On the phone", "Nobody", "$0"],
        ["A question to a cloud model", f"`{cheap}` to `{grok}`", "The key's owner, or the plan", f"{money(question(cheap))} to {money(question(grok))}"],
        ["One look, or a described scene with no on-device model", f"`{cheap}` to `{grok}`", "The key's owner, or the plan", f"{money(look(cheap))} to {money(look(grok))}"],
        [f"Guide mode's cloud hazard checks, a whole session at its limit of {GUIDE_CHECKS_PER_SESSION}", f"`{grok}`, with the wearer's own key", "The key's owner", f"at most {money(GUIDE_CHECKS_PER_SESSION * look(grok))}"],
        ["A task for one assistant", f"`{grok}`, {BOT_INPUT_TOKENS:,} tokens in and {BOT_OUTPUT_TOKENS} out", "Whoever runs the assistant", money(bot_turn())],
        [f"All hands, or a council of {TEAM_SIZE}", f"`{grok}`, once for each assistant", "Whoever runs the assistants", money(all_hands())],
        ["An hour of waiting for alerts on a relay, as built", "Cloudflare Durable Object, long poll", "Whoever runs the relay", money(relay_hour())],
        ["A push alert", "Apple Push Notification service", "Nobody", "$0"],
        ["A minute of live voice and video", "Gemini 3.8 Live, at its per-minute prices", "The key's owner", money(live_minute())],
        ["A minute of live voice", "xAI voice", "The key's owner", money(XAI_VOICE)],
    ]
    return table(["What happens", "Route", "Who is billed", "Cost"], rows)


def own_key_table() -> str:
    rows = [[f"`{name}`"] + [money(own_key_month(usage, name)) for usage in USAGE] for name in MODELS]
    return table(["Model"] + [f"{usage.name} month" for usage in USAGE], rows)


def usage_table() -> str:
    rows = [
        [usage.name, str(usage.questions_per_day), str(usage.looks_per_day), str(usage.bot_tasks_per_day), str(usage.all_hands_per_day)]
        for usage in USAGE
    ]
    return table(["Use", "Questions a day", "Looks a day", "Assistant tasks a day", "All hands a day"], rows)


def relay_table() -> str:
    month = DAYS * 24 * relay_hour()
    rows = [
        ["The phone waits with a long poll two hours a day", money(DAYS * 2 * relay_hour())],
        ["The phone waits with a long poll all day and night", money(month)],
        ["One assistant polls all day and night, with no webhook", money(month)],
        [f"{TEAM_SIZE} assistants poll all day and night", money(TEAM_SIZE * month)],
        ["The same waits on hibernating WebSockets and webhooks, 1,000 turns", money(1_000 * relay_turn())],
    ]
    return table(["A hosted relay for one subscriber, for a month", "Cloudflare cost"], rows)


def plans_table() -> str:
    rows = []
    for plan in PLANS:
        if plan.monthly == 0:
            rows.append([plan.name, "$0", "$0", "$0", "$0", "None"])
            continue
        allowance = "None needed"
        if plan.questions:
            allowance = f"{plan.questions:,} questions and {plan.looks:,} looks"
        if plan.bot_turns:
            allowance += f", {plan.bot_turns:,} assistant turns"
        rows.append([
            plan.name,
            money(plan.monthly),
            money(plan.yearly),
            money(net(plan.monthly, SMALL_BUSINESS_COMMISSION)),
            money(net(plan.monthly, STANDARD_COMMISSION)),
            allowance,
        ])
    return table(["Plan", "A month", "A year", "Kept from a month at 15%", "Kept from a month at 30%", "Hosted allowance a month"], rows)


def margins_table() -> str:
    rows = []
    for plan in PLANS:
        if plan.monthly == 0:
            continue
        row = [plan.name]
        for usage in USAGE:
            cost = hosted_month(plan, usage)
            row.append(f"{money(cost)}, {percent(margin(plan.monthly, SMALL_BUSINESS_COMMISSION, cost))}")
        cap = cap_month(plan)
        row.append(f"{money(cap)}, {percent(margin(plan.monthly, SMALL_BUSINESS_COMMISSION, cap))}")
        row.append(percent(margin(plan.yearly / 12, SMALL_BUSINESS_COMMISSION, cap)))
        row.append(percent(margin(plan.monthly, STANDARD_COMMISSION, cap)))
        rows.append(row)
    header = ["Plan"] + [f"{usage.name}: cost, margin" for usage in USAGE]
    header += ["Whole allowance: cost, margin", "Whole allowance, yearly price", "Whole allowance, 30% commission"]
    return table(header, rows)


def routing_table() -> str:
    plan = next(plan for plan in PLANS if plan.name == "Included AI")
    rows = []
    for name in (HOSTED_MODEL, "gpt-4o-mini", "claude-haiku-4-5", "grok-4.3"):
        cost = plan.questions * question(name) + plan.looks * look(name)
        rows.append([f"`{name}`", money(cost), percent(margin(plan.monthly, SMALL_BUSINESS_COMMISSION, cost))])
    return table(["Every hosted turn sent to", "Whole allowance costs", "Margin on Included AI"], rows)


def fixed_table() -> str:
    typical = next(usage for usage in USAGE if usage.name == "Typical")
    rows = [
        ["Apple Developer Program", money(DEVELOPER_PROGRAM_YEARLY), f"[apple-membership]({SOURCES['apple-membership']})"],
        ["Cloudflare Workers Paid, twelve months", money(12 * WORKERS_PAID_MONTHLY), f"[cloudflare]({SOURCES['cloudflare']})"],
        ["Total", money(fixed_yearly()), ""],
    ]
    for plan in PLANS:
        if plan.monthly:
            rows.append([f"{plan.name} subscribers, typical use, that cover it", str(subscribers_to_cover_fixed(plan, typical)), ""])
    return table(["Fixed cost a year", "Amount", "Source"], rows)


def free_table() -> str:
    cost = free_descriptions_month()
    kept = net(next(plan for plan in PLANS if plan.name == "Included AI").monthly, SMALL_BUSINESS_COMMISSION)
    rows = [
        [f"{FREE_DESCRIPTIONS_PER_DAY} described scenes a day for a month, on `{HOSTED_MODEL}`", money(cost)],
        ["Free users at that rate paid for by one Included AI subscription, before its own costs", str(int(kept // cost))],
    ]
    return table(["Free described scenes, if they are ever hosted", "Figure"], rows)


TABLES = {
    "prices": prices_table,
    "per-use": per_use_table,
    "features": features_table,
    "own-key": own_key_table,
    "usage": usage_table,
    "relay": relay_table,
    "plans": plans_table,
    "margins": margins_table,
    "routing": routing_table,
    "fixed": fixed_table,
    "free": free_table,
}


def block(name: str) -> str:
    return f"<!-- cost-model:{name} -->\n{TABLES[name]()}\n<!-- /cost-model:{name} -->"


def rewrite(document: str) -> str:
    """The document with each marked table replaced by the current one."""
    for name in TABLES:
        pattern = re.compile(rf"<!-- cost-model:{re.escape(name)} -->.*?<!-- /cost-model:{re.escape(name)} -->", re.DOTALL)
        if not pattern.search(document):
            raise ValueError(f"The document has no table marked cost-model:{name}.")
        document = pattern.sub(lambda _: block(name), document)
    return document


def main(arguments: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", metavar="DOC", help="Rewrite the tables inside DOC.")
    parser.add_argument("--check", metavar="DOC", help="Fail if DOC's tables are out of date.")
    options = parser.parse_args(arguments)

    missed = targets_missed()
    for line in missed:
        print(f"Margin target missed: {line}", file=sys.stderr)

    path = options.write or options.check
    if path is None:
        for name in TABLES:
            print(f"## {name}\n\n{TABLES[name]()}\n")
        return 1 if missed else 0

    with open(path, encoding="utf-8") as file:
        current = file.read()
    wanted = rewrite(current)
    if options.write:
        with open(path, "w", encoding="utf-8") as file:
            file.write(wanted)
        print(f"Wrote {len(TABLES)} tables to {path}.")
    elif wanted != current:
        print(f"{path} is out of date. Run: python3 scripts/cost_model.py --write {path}", file=sys.stderr)
        return 1
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
