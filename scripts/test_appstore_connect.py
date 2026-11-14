# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Tests for appstore_connect.py. Run with: python3 -m unittest discover -s scripts"""

import base64
import json
import os
import subprocess
import tempfile
import unittest
import urllib.parse

import appstore_connect as asc


def der_integer(value: bytes) -> bytes:
    value = value.lstrip(b"\x00") or b"\x00"
    if value[0] & 0x80:
        value = b"\x00" + value
    return b"\x02" + bytes([len(value)]) + value


def der_signature(raw: bytes) -> bytes:
    body = der_integer(raw[:32]) + der_integer(raw[32:])
    return b"\x30" + bytes([len(body)]) + body


class FakeApple:
    """Answers from a table of (method, path) and keeps every request."""

    def __init__(self, answers):
        self.answers = answers
        self.requests = []

    def __call__(self, method, url, headers, body):
        parts = urllib.parse.urlsplit(url)
        query = dict(urllib.parse.parse_qsl(parts.query))
        self.requests.append({"method": method, "path": parts.path, "query": query, "headers": headers, "body": json.loads(body) if body else None})
        answer = self.answers[(method, parts.path)]
        if callable(answer):
            answer = answer(self.requests[-1])
        status, payload = answer
        return status, json.dumps(payload).encode()

    def client(self):
        return asc.Client(token=lambda: "token", send=self)


def bundle_page(capabilities):
    return {
        "data": [
            # The filter is a prefix match, so a longer identifier can come back first.
            {"id": "OTHER", "attributes": {"identifier": "com.example.app.widget"}, "relationships": {"bundleIdCapabilities": {"data": [{"id": "c9"}]}}},
            {"id": "BUNDLE", "attributes": {"identifier": "com.example.app"}, "relationships": {"bundleIdCapabilities": {"data": [{"id": f"c{i}"} for i in range(len(capabilities))]}}},
        ],
        "included": [{"type": "bundleIdCapabilities", "id": f"c{i}", "attributes": {"capabilityType": c}} for i, c in enumerate(capabilities)]
        + [{"type": "bundleIdCapabilities", "id": "c9", "attributes": {"capabilityType": "ASSOCIATED_DOMAINS"}}],
    }


class SigningTests(unittest.TestCase):
    def test_raw_signature_pads_short_integers_and_drops_sign_bytes(self):
        r = b"\x00" * 2 + b"\x7f" + b"\x11" * 29
        s = b"\x80" + b"\x22" * 31
        raw = asc.raw_signature(der_signature(r + s))
        self.assertEqual(raw, r + s)
        self.assertEqual(len(raw), 64)

    def test_raw_signature_refuses_what_is_not_a_signature(self):
        for bad in (b"", b"\x31\x00", b"\x30\x03\x04\x01\x01", der_signature(b"\x01" * 64) + b"\x00"):
            with self.assertRaises(ValueError):
                asc.raw_signature(bad)

    def test_token_verifies_with_the_public_key(self):
        with tempfile.TemporaryDirectory() as folder:
            key = os.path.join(folder, "key.p8")
            public = os.path.join(folder, "public.pem")
            subprocess.run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", key], check=True, capture_output=True)
            subprocess.run(["openssl", "pkey", "-in", key, "-pubout", "-out", public], check=True, capture_output=True)

            token = asc.make_token("KEYID", "ISSUER", lambda message: asc.openssl_sign(key, message), now=1_800_000_000)
            header, claims, signature = token.split(".")

            def decode(part):
                return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))

            self.assertEqual(json.loads(decode(header)), {"alg": "ES256", "kid": "KEYID", "typ": "JWT"})
            self.assertEqual(json.loads(decode(claims)), {"iss": "ISSUER", "iat": 1_800_000_000, "exp": 1_800_000_900, "aud": "appstoreconnect-v1"})

            signature_file = os.path.join(folder, "signature.der")
            with open(signature_file, "wb") as out:
                out.write(der_signature(decode(signature)))
            verified = subprocess.run(
                ["openssl", "dgst", "-sha256", "-verify", public, "-signature", signature_file],
                input=f"{header}.{claims}".encode(), capture_output=True, check=False,
            )
            self.assertEqual(verified.returncode, 0, verified.stdout)

    def test_a_bad_key_does_not_echo_openssl_output(self):
        with tempfile.NamedTemporaryFile("w", suffix=".p8") as key:
            key.write("-----BEGIN PRIVATE KEY-----\nnot-a-key\n-----END PRIVATE KEY-----\n")
            key.flush()
            with self.assertRaises(SystemExit) as stopped:
                asc.openssl_sign(key.name, b"message")
            self.assertNotIn("not-a-key", str(stopped.exception))


class ClientTests(unittest.TestCase):
    def test_requests_carry_the_token_and_a_named_agent(self):
        apple = FakeApple({("GET", "/v1/apps"): (200, {"data": []})})
        apple.client().get("/v1/apps", {"limit": "1"})
        headers = apple.requests[0]["headers"]
        self.assertEqual(headers["Authorization"], "Bearer token")
        self.assertTrue(headers["User-Agent"].startswith("PhoenixFox-CI/"))
        self.assertEqual(apple.requests[0]["query"], {"limit": "1"})

    def test_errors_carry_apples_reason(self):
        apple = FakeApple({("GET", "/v1/apps"): (403, {"errors": [{"code": "FORBIDDEN_ERROR", "detail": "This key cannot do that."}]})})
        with self.assertRaises(asc.ApiError) as raised:
            apple.client().get("/v1/apps")
        self.assertEqual(raised.exception.status, 403)
        self.assertEqual(raised.exception.detail, "FORBIDDEN_ERROR: This key cannot do that.")


class CapabilityTests(unittest.TestCase):
    def test_only_missing_capabilities_are_requested(self):
        apple = FakeApple({
            ("GET", "/v1/bundleIds"): (200, bundle_page(["PUSH_NOTIFICATIONS"])),
            ("POST", "/v1/bundleIdCapabilities"): (201, {"data": {"id": "new"}}),
        })
        report = asc.ensure_capabilities(apple.client(), "com.example.app", ["PUSH_NOTIFICATIONS", "ASSOCIATED_DOMAINS"])
        self.assertEqual(report.already, ["PUSH_NOTIFICATIONS"])
        self.assertEqual(report.enabled, ["ASSOCIATED_DOMAINS"])
        self.assertEqual(report.refused, {})
        posts = [r for r in apple.requests if r["method"] == "POST"]
        self.assertEqual(len(posts), 1)
        data = posts[0]["body"]["data"]
        self.assertEqual(data["attributes"]["capabilityType"], "ASSOCIATED_DOMAINS")
        self.assertEqual(data["relationships"]["bundleId"]["data"], {"type": "bundleIds", "id": "BUNDLE"})

    def test_a_refused_capability_is_reported_and_the_rest_still_run(self):
        def post(request):
            if request["body"]["data"]["attributes"]["capabilityType"] == "INCREASED_MEMORY_LIMIT":
                return 409, {"errors": [{"code": "ENTITY_ERROR.ATTRIBUTE.INVALID", "detail": "Not a capability type."}]}
            return 201, {"data": {"id": "new"}}

        apple = FakeApple({("GET", "/v1/bundleIds"): (200, bundle_page([])), ("POST", "/v1/bundleIdCapabilities"): post})
        report = asc.ensure_capabilities(apple.client(), "com.example.app", ["INCREASED_MEMORY_LIMIT", "ASSOCIATED_DOMAINS"])
        self.assertEqual(report.enabled, ["ASSOCIATED_DOMAINS"])
        self.assertEqual(list(report.refused), ["INCREASED_MEMORY_LIMIT"])

    def test_an_unregistered_app_id_stops_with_a_clear_message(self):
        apple = FakeApple({("GET", "/v1/bundleIds"): (200, {"data": []})})
        with self.assertRaises(SystemExit) as stopped:
            asc.ensure_capabilities(apple.client(), "com.example.app", ["ASSOCIATED_DOMAINS"])
        self.assertIn("com.example.app", str(stopped.exception))


class GroupTests(unittest.TestCase):
    def test_an_existing_internal_group_is_reused(self):
        apple = FakeApple({("GET", "/v1/apps/APP/betaGroups"): (200, {"data": [
            {"id": "EXTERNAL", "attributes": {"name": "Team", "isInternalGroup": False}},
            {"id": "INTERNAL", "attributes": {"name": "Team", "isInternalGroup": True}},
        ]})})
        self.assertEqual(asc.ensure_internal_group(apple.client(), "APP", "Team"), ("INTERNAL", False))

    def test_a_missing_group_is_created_with_every_build(self):
        apple = FakeApple({
            ("GET", "/v1/apps/APP/betaGroups"): (200, {"data": []}),
            ("POST", "/v1/betaGroups"): (201, {"data": {"id": "NEW"}}),
        })
        self.assertEqual(asc.ensure_internal_group(apple.client(), "APP", "Team"), ("NEW", True))
        data = apple.requests[-1]["body"]["data"]
        self.assertEqual(data["attributes"], {"name": "Team", "isInternalGroup": True, "hasAccessToAllBuilds": True})
        self.assertEqual(data["relationships"]["app"]["data"]["id"], "APP")

    def test_the_log_line_never_names_the_account_holder(self):
        holder = {"data": [{"attributes": {"username": "owner@example.com", "firstName": "Pat", "lastName": "Owner"}}]}
        for status, payload in ((201, {"data": {"id": "T"}}), (409, {"errors": [{"detail": "owner@example.com is already a tester"}]}), (403, {"errors": [{"detail": "owner@example.com"}]})):
            apple = FakeApple({("GET", "/v1/users"): (200, holder), ("POST", "/v1/betaTesters"): (status, payload)})
            line = asc.add_account_holder(apple.client(), "GROUP")
            for private in ("owner@example.com", "Pat", "Owner"):
                self.assertNotIn(private, line)
            self.assertEqual(apple.requests[-1]["body"]["data"]["attributes"]["email"], "owner@example.com")

    def test_a_key_that_cannot_read_users_gives_the_manual_step(self):
        apple = FakeApple({("GET", "/v1/users"): (403, {"errors": [{"code": "FORBIDDEN_ERROR"}]})})
        self.assertIn("Add yourself", asc.add_account_holder(apple.client(), "GROUP"))


class BuildTests(unittest.TestCase):
    def wait(self, states, timeout=300):
        remaining = list(states)
        clock = [0.0]

        def builds(_request):
            state = remaining.pop(0) if len(remaining) > 1 else remaining[0]
            if isinstance(state, int):
                return state, {"errors": [{"code": "ERROR"}]}
            return 200, {"data": [] if state is None else [{"attributes": {"processingState": state}}]}

        apple = FakeApple({("GET", "/v1/builds"): builds})
        result = asc.wait_for_build(
            apple.client(), "APP", "1.0.0", "42.1", timeout,
            sleep=lambda seconds: clock.__setitem__(0, clock[0] + seconds), now=lambda: clock[0],
        )
        return result, apple

    def test_waits_through_processing(self):
        result, apple = self.wait([None, "PROCESSING", "PROCESSING", "VALID"])
        self.assertEqual(result, "VALID")
        self.assertEqual(len(apple.requests), 4)
        self.assertEqual(apple.requests[0]["query"]["filter[version]"], "42.1")
        self.assertEqual(apple.requests[0]["query"]["filter[preReleaseVersion.version]"], "1.0.0")

    def test_reports_a_rejected_build(self):
        self.assertEqual(self.wait(["PROCESSING", "INVALID"])[0], "INVALID")

    def test_gives_up_after_the_timeout(self):
        result, apple = self.wait(["PROCESSING"], timeout=90)
        self.assertEqual(result, "TIMED_OUT")
        self.assertEqual(len(apple.requests), 4)

    def test_a_server_error_is_waited_out(self):
        self.assertEqual(self.wait(["PROCESSING", 503, "VALID"])[0], "VALID")

    def test_a_refused_key_stops_at_once(self):
        with self.assertRaises(asc.ApiError):
            self.wait([401])


if __name__ == "__main__":
    unittest.main()
