#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Prepare App Store Connect for a Phoenix Fox upload, and check on the build after it.

The TestFlight workflow runs this. It needs only Python and `openssl`, both of which are
on every GitHub runner.

    appstore_connect.py capabilities --bundle-id ID --enable ASSOCIATED_DOMAINS ...
    appstore_connect.py beta-group --bundle-id ID --name "Phoenix Fox team"
    appstore_connect.py wait-build --bundle-id ID --version 1.0.0 --build 42.1

The key comes from the environment: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH (the .p8
file). The job log of a public repository is public, so nothing here prints a name, an
email address, or any part of the key.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable, Iterable

API = "https://api.appstoreconnect.apple.com"
AGENT = "PhoenixFox-CI/1.0 (+https://github.com/cinderandcrown/phoenix-fox)"

# What the app's entitlements need on its App ID, with the name Apple's website uses.
CAPABILITY_NAMES = {
    "ASSOCIATED_DOMAINS": "Associated Domains",
    "PUSH_NOTIFICATIONS": "Push Notifications",
    "INCREASED_MEMORY_LIMIT": "Increased Memory Limit",
}


class ApiError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(f"App Store Connect answered {status}: {detail}")
        self.status = status
        self.detail = detail


# --- Signing -----------------------------------------------------------------------------


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def raw_signature(der: bytes) -> bytes:
    """Turns openssl's DER signature into the 64 bytes (r then s) that a JWT carries."""

    def read_length(at: int) -> tuple[int, int]:
        first = der[at]
        if first < 0x80:
            return first, at + 1
        count = first & 0x7F
        return int.from_bytes(der[at + 1 : at + 1 + count], "big"), at + 1 + count

    def read_integer(at: int) -> tuple[bytes, int]:
        if der[at] != 0x02:
            raise ValueError("not a DER integer")
        length, start = read_length(at + 1)
        value = der[start : start + length].lstrip(b"\x00")
        if len(value) > 32:
            raise ValueError("integer too large for P-256")
        return value.rjust(32, b"\x00"), start + length

    if not der or der[0] != 0x30:
        raise ValueError("not a DER sequence")
    _, at = read_length(1)
    r, at = read_integer(at)
    s, at = read_integer(at)
    if at != len(der):
        raise ValueError("unexpected data after the signature")
    return r + s


def openssl_sign(key_path: str, message: bytes) -> bytes:
    done = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=message,
        capture_output=True,
        check=False,
    )
    if done.returncode != 0:
        # openssl's message can quote the key file. Say only that it failed.
        raise SystemExit("Could not sign with the App Store Connect key. Check the ASC_KEY_P8 secret.")
    return done.stdout


def make_token(
    key_id: str,
    issuer_id: str,
    sign: Callable[[bytes], bytes],
    now: float,
    lifetime: int = 15 * 60,
) -> str:
    """A token App Store Connect accepts. Apple refuses lifetimes over twenty minutes."""
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {"iss": issuer_id, "iat": int(now), "exp": int(now) + lifetime, "aud": "appstoreconnect-v1"}
    signing_input = ".".join(base64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, claims))
    return f"{signing_input}.{base64url(raw_signature(sign(signing_input.encode())))}"


# --- HTTP --------------------------------------------------------------------------------

Send = Callable[[str, str, dict[str, str], bytes | None], tuple[int, bytes]]


def urllib_send(method: str, url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


@dataclass
class Client:
    token: Callable[[], str]
    send: Send = urllib_send

    def call(self, method: str, path: str, query: dict[str, str] | None = None, body: Any = None) -> Any:
        url = path if path.startswith("https://") else API + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {"Authorization": f"Bearer {self.token()}", "Accept": "application/json", "User-Agent": AGENT}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        status, raw = self.send(method, url, headers, data)
        parsed = json.loads(raw) if raw else {}
        if status >= 400:
            raise ApiError(status, describe_errors(parsed))
        return parsed

    def get(self, path: str, query: dict[str, str] | None = None) -> Any:
        return self.call("GET", path, query)

    def post(self, path: str, body: Any) -> Any:
        return self.call("POST", path, body=body)


def describe_errors(body: Any) -> str:
    errors = body.get("errors") if isinstance(body, dict) else None
    if not errors:
        return "no detail"
    return "; ".join(f"{e.get('code', '?')}: {e.get('detail') or e.get('title') or ''}".strip() for e in errors)


# --- App ID capabilities -----------------------------------------------------------------


def find_bundle(client: Client, identifier: str) -> dict[str, Any]:
    """The App ID record, with the capabilities it has now under `capabilities`."""
    page = client.get(
        "/v1/bundleIds",
        {"filter[identifier]": identifier, "include": "bundleIdCapabilities", "limit": "200"},
    )
    # The filter matches any identifier that starts with the text, so compare exactly.
    for bundle in page.get("data", []):
        if bundle["attributes"]["identifier"] == identifier:
            wanted = {link["id"] for link in bundle.get("relationships", {}).get("bundleIdCapabilities", {}).get("data", [])}
            enabled = {
                item["attributes"]["capabilityType"]
                for item in page.get("included", [])
                if item["type"] == "bundleIdCapabilities" and item["id"] in wanted
            }
            return {"id": bundle["id"], "capabilities": enabled}
    raise SystemExit(f"No App ID {identifier} in this Apple Developer account. Register it first.")


@dataclass
class CapabilityReport:
    already: list[str]
    enabled: list[str]
    refused: dict[str, str]


def ensure_capabilities(client: Client, identifier: str, wanted: Iterable[str]) -> CapabilityReport:
    bundle = find_bundle(client, identifier)
    report = CapabilityReport(already=[], enabled=[], refused={})
    for capability in wanted:
        if capability in bundle["capabilities"]:
            report.already.append(capability)
            continue
        try:
            client.post(
                "/v1/bundleIdCapabilities",
                {
                    "data": {
                        "type": "bundleIdCapabilities",
                        "attributes": {"capabilityType": capability, "settings": []},
                        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}}},
                    }
                },
            )
            report.enabled.append(capability)
        except ApiError as error:
            report.refused[capability] = error.detail
    return report


def print_capability_report(report: CapabilityReport, identifier: str) -> None:
    def name(capability: str) -> str:
        return CAPABILITY_NAMES.get(capability, capability)

    for capability in report.already:
        print(f"Already on: {name(capability)}")
    for capability in report.enabled:
        print(f"Turned on: {name(capability)}")
    for capability, why in report.refused.items():
        print(f"Could not turn on {name(capability)}: {why}")
    if report.refused:
        names = ", ".join(name(capability) for capability in report.refused)
        print(
            "\nThe App Store Connect API does not manage every capability. If signing fails below,\n"
            f"turn on {names} by hand: developer.apple.com/account > Identifiers > {identifier} >\n"
            "Capabilities (or Capability Requests), then run this workflow again."
        )


# --- TestFlight group --------------------------------------------------------------------


def find_app(client: Client, identifier: str) -> str:
    page = client.get("/v1/apps", {"filter[bundleId]": identifier, "limit": "10"})
    for app in page.get("data", []):
        if app["attributes"]["bundleId"] == identifier:
            return app["id"]
    raise SystemExit(f"No app with bundle ID {identifier} in App Store Connect. Create the app record first.")


def ensure_internal_group(client: Client, app_id: str, name: str) -> tuple[str, bool]:
    """An internal group that gets every build. Returns its id and whether it is new."""
    page = client.get(f"/v1/apps/{app_id}/betaGroups", {"limit": "200"})
    for group in page.get("data", []):
        attributes = group["attributes"]
        if attributes.get("isInternalGroup") and attributes.get("name") == name:
            return group["id"], False
    created = client.post(
        "/v1/betaGroups",
        {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": name, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    return created["data"]["id"], True


def add_account_holder(client: Client, group_id: str) -> str:
    """Puts the account holder in the group. Returns a sentence for the log, with no names."""
    try:
        holders = client.get("/v1/users", {"filter[roles]": "ACCOUNT_HOLDER", "limit": "1"}).get("data", [])
    except ApiError as error:
        return f"Could not read the team's users ({error.status}). Add yourself to the group in App Store Connect > TestFlight."
    if not holders:
        return "No account holder was listed. Add yourself to the group in App Store Connect > TestFlight."
    holder = holders[0]["attributes"]
    try:
        client.post(
            "/v1/betaTesters",
            {
                "data": {
                    "type": "betaTesters",
                    "attributes": {
                        "email": holder["username"],
                        "firstName": holder.get("firstName") or "",
                        "lastName": holder.get("lastName") or "",
                    },
                    "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group_id}]}},
                }
            },
        )
        return "The account holder is in the group."
    except ApiError as error:
        if error.status == 409:
            return "The account holder was already a tester."
        return f"Could not add the account holder ({error.status}). Add yourself to the group in App Store Connect > TestFlight."


# --- Build processing --------------------------------------------------------------------


def build_state(client: Client, app_id: str, version: str, build: str) -> str | None:
    page = client.get(
        "/v1/builds",
        {
            "filter[app]": app_id,
            "filter[version]": build,
            "filter[preReleaseVersion.version]": version,
            "limit": "1",
        },
    )
    builds = page.get("data", [])
    return builds[0]["attributes"].get("processingState") if builds else None


def wait_for_build(
    client: Client,
    app_id: str,
    version: str,
    build: str,
    timeout: float,
    sleep: Callable[[float], None] = time.sleep,
    now: Callable[[], float] = time.monotonic,
) -> str:
    """Waits until Apple finishes processing. Returns VALID, INVALID, FAILED, or TIMED_OUT."""
    deadline = now() + timeout
    last = None
    while True:
        try:
            state = build_state(client, app_id, version, build)
        except ApiError as error:
            if error.status < 500 and error.status != 429:
                raise
            state = last
        if state != last:
            print(f"Build {version} ({build}): {state or 'not listed yet'}")
            last = state
        if state in ("VALID", "INVALID", "FAILED"):
            return state
        if now() >= deadline:
            return "TIMED_OUT"
        sleep(30)


# --- Command line ------------------------------------------------------------------------


def client_from_environment() -> Client:
    missing = [name for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH") if not os.environ.get(name)]
    if missing:
        raise SystemExit("Missing: " + ", ".join(missing))
    key_id, issuer_id, key_path = (os.environ[name] for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"))
    cached: dict[str, Any] = {}

    def token() -> str:
        # A token lasts fifteen minutes. Waiting for a build takes longer, so renew it.
        if not cached or time.time() > cached["made"] + 10 * 60:
            cached["made"] = time.time()
            cached["token"] = make_token(key_id, issuer_id, lambda message: openssl_sign(key_path, message), time.time())
        return cached["token"]

    return Client(token=token)


def main(arguments: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    capabilities = commands.add_parser("capabilities", help="turn on App ID capabilities")
    capabilities.add_argument("--bundle-id", required=True)
    capabilities.add_argument("--enable", nargs="+", required=True)

    group = commands.add_parser("beta-group", help="make sure an internal TestFlight group exists")
    group.add_argument("--bundle-id", required=True)
    group.add_argument("--name", required=True)

    wait = commands.add_parser("wait-build", help="wait for Apple to process an uploaded build")
    wait.add_argument("--bundle-id", required=True)
    wait.add_argument("--version", required=True)
    wait.add_argument("--build", required=True)
    wait.add_argument("--timeout", type=float, default=30 * 60)

    options = parser.parse_args(arguments)
    client = client_from_environment()

    try:
        if options.command == "capabilities":
            report = ensure_capabilities(client, options.bundle_id, options.enable)
            print_capability_report(report, options.bundle_id)
            return 0
        if options.command == "beta-group":
            app_id = find_app(client, options.bundle_id)
            group_id, created = ensure_internal_group(client, app_id, options.name)
            print(f"Internal group “{options.name}”: {'created' if created else 'already there'}. It gets every build.")
            print(add_account_holder(client, group_id))
            return 0
        if options.command == "wait-build":
            app_id = find_app(client, options.bundle_id)
            state = wait_for_build(client, app_id, options.version, options.build, options.timeout)
            if state == "VALID":
                print("Apple finished processing. The build is in TestFlight.")
                return 0
            if state == "TIMED_OUT":
                print("Apple is still processing. The build will appear in TestFlight when it finishes.")
                return 0
            print("Apple rejected the build during processing. The reason is in the email from App Store Connect.")
            return 1
    except ApiError as error:
        print(f"{error}")
        if error.status in (401, 403):
            print("The key was refused. Check ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, and the key's role.")
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
