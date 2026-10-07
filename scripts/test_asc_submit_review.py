#!/usr/bin/env python3
"""Unit tests for the pure helpers in asc_submit_review.py."""

import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import asc_submit_review as asc

FIXTURE = pathlib.Path(__file__).resolve().parent / "fixtures" / "asc_versions.json"


def versions():
    return json.loads(FIXTURE.read_text())["data"]


class VersionSelectionTests(unittest.TestCase):
    def test_live_version_is_highest_ready_for_sale_ios(self):
        live = asc.pick_live_version(versions())
        self.assertEqual(live["id"], "live-358")
        self.assertEqual(live["attributes"]["releaseType"], "AFTER_APPROVAL")

    def test_reusable_draft_is_returned(self):
        draft = asc.pick_reusable_version(versions(), "3.6.1")
        self.assertEqual(draft["id"], "draft-361")

    def test_rejected_version_is_reusable(self):
        rejected = asc.pick_reusable_version(versions(), "3.4.0")
        self.assertEqual(rejected["id"], "rejected-340")

    def test_missing_version_returns_none(self):
        self.assertIsNone(asc.pick_reusable_version(versions(), "9.9.9"))

    def test_in_review_version_is_not_reusable(self):
        with self.assertRaises(asc.AscFailure) as caught:
            asc.pick_reusable_version(versions(), "3.6.0")
        self.assertIn("WAITING_FOR_REVIEW", str(caught.exception))
        self.assertIn("waiting-360", str(caught.exception))

    def test_open_version_blocks_creating_a_different_one(self):
        blocker = asc.blocking_version(versions(), "9.9.9")
        self.assertEqual(blocker["id"], "draft-361")

    def test_ready_for_sale_and_old_rejection_do_not_block_create(self):
        kept = [
            version for version in versions()
            if version["attributes"]["appStoreState"] in {"READY_FOR_SALE", "REJECTED"}
        ]
        self.assertIsNone(asc.blocking_version(kept, "3.6.1"))


class BuildAndMetadataTests(unittest.TestCase):
    def test_select_build_skips_expired_and_prefers_valid(self):
        builds = [
            {"id": "old", "attributes": {"expired": False, "processingState": "PROCESSING", "uploadedDate": "2026-10-01T00:00:00Z"}},
            {"id": "expired", "attributes": {"expired": True, "processingState": "VALID", "uploadedDate": "2026-10-02T00:00:00Z"}},
            {"id": "valid", "attributes": {"expired": False, "processingState": "VALID", "uploadedDate": "2026-10-01T12:00:00Z"}},
        ]
        self.assertEqual(asc.select_build(builds)["id"], "valid")

    def test_expired_only_builds_fail(self):
        with self.assertRaises(asc.AscFailure) as caught:
            asc.select_build([{"id": "e", "attributes": {"expired": True}}])
        self.assertIn("expired", str(caught.exception))

    def test_payload_filter_checks_train_and_build_number(self):
        payload = {
            "data": [
                {
                    "id": "keep",
                    "attributes": {"version": "10007"},
                    "relationships": {"preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": "train"}}},
                },
                {
                    "id": "other-train",
                    "attributes": {"version": "10007"},
                    "relationships": {"preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": "other"}}},
                },
                {
                    "id": "other-build",
                    "attributes": {"version": "10008"},
                    "relationships": {"preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": "train"}}},
                },
            ],
            "included": [
                {"type": "preReleaseVersions", "id": "train", "attributes": {"version": "3.6.1", "platform": "IOS"}},
                {"type": "preReleaseVersions", "id": "other", "attributes": {"version": "3.6.0", "platform": "IOS"}},
            ],
        }
        matched = asc.builds_from_payload(payload, "3.6.1", "10007")
        self.assertEqual([build["id"] for build in matched], ["keep"])

    def test_encryption_flag(self):
        self.assertEqual(asc.encryption_to_set(False, True), (None, "already set"))
        self.assertEqual(asc.encryption_to_set(None, True)[0], True)
        self.assertEqual(asc.encryption_to_set(None, False)[0], False)
        value, reason = asc.encryption_to_set(None, None)
        self.assertEqual(value, False)
        self.assertIn("false", reason)

    def test_localization_fills_only_empty_required_fields(self):
        patch = asc.localization_patch(
            {"locale": "en-US", "description": "Already set", "keywords": "", "supportUrl": None, "promotionalText": ""},
            {"description": "Live description", "keywords": "football", "supportUrl": "https://pickems-fb.web.app/support", "promotionalText": "Live promo"},
            "Bug fixes.",
        )
        self.assertEqual(patch["whatsNew"], "Bug fixes.")
        self.assertNotIn("description", patch)
        self.assertEqual(patch["keywords"], "football")
        self.assertEqual(patch["supportUrl"], "https://pickems-fb.web.app/support")
        self.assertNotIn("promotionalText", patch)

    def test_idfa_status(self):
        self.assertEqual(asc.idfa_status_from_response(200, {"data": {"id": "abc"}}), "present")
        self.assertEqual(asc.idfa_status_from_response(200, {"data": None}), "absent")
        self.assertEqual(asc.idfa_status_from_response(404, None), "absent")
        self.assertEqual(asc.idfa_status_from_response(403, {"errors": []}), "not readable")


class SubmissionSelectionTests(unittest.TestCase):
    def test_reuses_ready_for_review_submission(self):
        submissions = [
            {"id": "complete", "attributes": {"state": "COMPLETE", "platform": "IOS", "createdDate": "2026-10-02T00:00:00Z"}},
            {"id": "older", "attributes": {"state": "READY_FOR_REVIEW", "platform": "IOS", "createdDate": "2026-10-01T00:00:00Z"}},
            {"id": "newer", "attributes": {"state": "READY_FOR_REVIEW", "platform": "IOS", "createdDate": "2026-10-03T00:00:00Z"}},
            {"id": "mac", "attributes": {"state": "READY_FOR_REVIEW", "platform": "MAC_OS", "createdDate": "2026-10-04T00:00:00Z"}},
        ]
        self.assertEqual(asc.pick_open_review_submission(submissions)["id"], "newer")

    def test_in_flight_submission_blocks(self):
        submissions = [
            {"id": "waiting", "attributes": {"state": "WAITING_FOR_REVIEW", "platform": "IOS"}},
        ]
        self.assertEqual(asc.blocking_review_submission(submissions)["id"], "waiting")
        self.assertIsNone(asc.pick_open_review_submission(submissions))

    def test_item_already_includes_version(self):
        items = [
            {"id": "item", "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": "ver-1"}}}},
        ]
        self.assertTrue(asc.submission_includes_version(items, "ver-1"))
        self.assertFalse(asc.submission_includes_version(items, "ver-2"))


class ErrorAndTokenTests(unittest.TestCase):
    def test_api_error_includes_detail(self):
        payload = {
            "errors": [
                {
                    "status": "409",
                    "code": "STATE_ERROR",
                    "title": "The request cannot be completed",
                    "detail": "Version is not editable.",
                }
            ]
        }
        message = asc.api_error_message("PATCH", "/v1/appStoreVersions/abc?fields=x", 409, payload)
        self.assertIn("Version is not editable.", message)
        self.assertIn("STATE_ERROR", message)
        self.assertNotIn("fields=x", message)

    def test_redact_strips_key_token_and_issuer(self):
        pem = "-----BEGIN PRIVATE KEY-----\nSECRETDATA\n-----END PRIVATE KEY-----\n"
        token = "eyJhbGciOiJFUzI1NiJ9.eyJpc3MiOiJ0ZXN0In0.signaturevalue"
        issuer = "11111111-2222-4333-8444-555555555555"
        text = f"failed with {pem} bearer {token} issuer {issuer}"
        redacted = asc.redact(text, [issuer])
        self.assertNotIn("SECRETDATA", redacted)
        self.assertNotIn(token, redacted)
        self.assertNotIn(issuer, redacted)
        self.assertIn("[REDACTED KEY]", redacted)
        self.assertIn("[REDACTED TOKEN]", redacted)

    def test_token_claims_are_es256_audience_and_twenty_minutes(self):
        claims = asc.token_claims("issuer-test", 1_700_000_000)
        self.assertEqual(claims["aud"], "appstoreconnect-v1")
        self.assertEqual(claims["exp"] - claims["iat"], 20 * 60)
        self.assertEqual(claims["iss"], "issuer-test")

    def test_make_token_round_trip_does_not_require_printing_it(self):
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives import serialization

        key = ec.generate_private_key(ec.SECP256R1())
        pem = key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ).decode()
        token = asc.make_token("KEYID12345", "issuer-test", pem, now=int(__import__("time").time()))
        decoded = jwt_decode(token, key.public_key())
        self.assertEqual(decoded["aud"], "appstoreconnect-v1")
        self.assertEqual(decoded["exp"] - decoded["iat"], 20 * 60)
        self.assertEqual(decoded["iss"], "issuer-test")
        self.assertNotIn("BEGIN PRIVATE KEY", token)

    def test_load_p8_accepts_pem_and_base64(self):
        import base64
        pem = "-----BEGIN PRIVATE KEY-----\nQUJD\n-----END PRIVATE KEY-----\n"
        literal = pem.replace("\n", "\\n")
        self.assertEqual(asc.load_p8(literal), pem)
        encoded = base64.b64encode(pem.encode()).decode()
        self.assertEqual(asc.load_p8(encoded), pem)
        with self.assertRaises(asc.AscFailure):
            asc.load_p8("not-a-key")

    def test_summary_includes_the_operator_fields(self):
        text = asc.format_summary({
            "bundle_id": "FannypackInc.Pickems",
            "app_id": "6785697079",
            "platform": "IOS",
            "build_number": "10007",
            "build_id": "build-1",
            "processing_state": "VALID",
            "encryption": False,
            "encryption_note": "already set",
            "version_string": "3.6.1",
            "version_id": "ver-1",
            "version_state": "PREPARE_FOR_SUBMISSION",
            "release_type": "AFTER_APPROVAL",
            "release_note": "copied AFTER_APPROVAL from the READY_FOR_SALE version",
            "attached_build_id": "build-1",
            "locales": ["en-US"],
            "locale_notes": ["en-US: whatsNew set."],
            "live_version_string": "3.5.8",
            "live_version_id": "live-358",
            "idfa": "present",
            "dry_run": True,
        })
        self.assertIn("processingState=VALID", text)
        self.assertIn("id=ver-1", text)
        self.assertIn("appStoreState=PREPARE_FOR_SUBMISSION", text)
        self.assertIn("releaseType=AFTER_APPROVAL", text)
        self.assertIn("Locales updated: en-US", text)
        self.assertIn("IDFA/ad declaration: present", text)
        self.assertIn("stopped before creating a review submission", text)

    def test_wait_returns_when_valid_without_sleeping(self):
        slept = []
        build = asc.wait_until_valid(
            lambda: {"id": "b", "attributes": {"processingState": "VALID"}},
            "10007",
            "b",
            sleep=slept.append,
            monotonic=lambda: 0,
        )
        self.assertEqual(build["id"], "b")
        self.assertEqual(slept, [])

    def test_wait_fails_immediately_when_invalid(self):
        slept = []
        with self.assertRaises(asc.AscFailure) as caught:
            asc.wait_until_valid(
                lambda: {"attributes": {"processingState": "INVALID"}},
                "10007",
                "b",
                sleep=slept.append,
                monotonic=lambda: 0,
            )
        self.assertIn("INVALID", str(caught.exception))
        self.assertEqual(slept, [])

    def test_wait_stops_at_the_timeout(self):
        clock = {"t": 0}

        def monotonic():
            return clock["t"]

        def sleep(seconds):
            clock["t"] += seconds

        with self.assertRaises(asc.AscFailure) as caught:
            asc.wait_until_valid(
                lambda: {"attributes": {"processingState": "PROCESSING"}},
                "10007",
                "b",
                sleep=sleep,
                monotonic=monotonic,
                interval=60,
                timeout=120,
            )
        self.assertIn("PROCESSING", str(caught.exception))
        self.assertIn("2 minutes", str(caught.exception))

    def test_dry_run_defaults_to_true(self):
        self.assertTrue(asc.parse_bool(None))
        self.assertTrue(asc.parse_bool("true"))
        self.assertFalse(asc.parse_bool("false"))


def jwt_decode(token, public_key):
    import jwt
    return jwt.decode(token, public_key, algorithms=["ES256"], audience="appstoreconnect-v1")


if __name__ == "__main__":
    unittest.main()
