#!/usr/bin/env python3
"""Cancel the open App Store review submission for one Pickems version.

Finds the iOS reviewSubmission (WAITING_FOR_REVIEW / IN_REVIEW / READY_FOR_REVIEW /
UNRESOLVED_ISSUES) whose items include the given appStoreVersion and sends
PATCH /v1/reviewSubmissions/{id} with attributes.canceled=true. The version then
returns to an editable state. Nothing else is changed.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_VERSION, ASC_DRY_RUN (default true).
"""
from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import asc_submit_review as asc  # noqa: E402

CANCELABLE_STATES = {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"}


def find_submission(client, version_id: str) -> dict | None:
    for sub in asc.list_review_submissions(client):
        attrs = asc._attrs(sub)
        if attrs.get("state") not in CANCELABLE_STATES:
            continue
        if attrs.get("platform") not in (None, asc.PLATFORM):
            continue
        if asc.submission_includes_version(asc.submission_items(client, sub["id"]), version_id):
            return sub
    return None


def run(client, version_string: str, dry_run: bool) -> int:
    versions = asc.list_versions(client)
    target = next(
        (v for v in versions if asc._is_ios(v) and asc._attrs(v).get("versionString") == version_string),
        None,
    )
    if not target:
        raise asc.AscFailure(f"No iOS appStoreVersion {version_string} found.")
    state_before = asc._attrs(target).get("appStoreState")
    asc.log(f"Version {version_string} ({target['id']}) state: {state_before}")
    sub = find_submission(client, target["id"])
    if not sub:
        raise asc.AscFailure(f"No cancelable review submission contains version {version_string}.")
    sub_state = asc._attrs(sub).get("state")
    asc.log(f"Review submission {sub['id']} state: {sub_state}")
    if dry_run:
        msg = f"Dry run: would cancel reviewSubmission {sub['id']} ({sub_state}) for {version_string} ({state_before})."
        asc.log(msg)
        asc.write_step_summary(msg)
        return 0

    asc.log(f"PATCH /v1/reviewSubmissions/{sub['id']} canceled=true")
    _, body = client.request(
        "PATCH",
        f"/v1/reviewSubmissions/{sub['id']}",
        json_body={"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"canceled": True}}},
    )
    sub_after = asc._attrs((body or {}).get("data")).get("state")
    version_after = state_before
    for _ in range(12):
        time.sleep(10)
        _, doc = client.request("GET", f"/v1/reviewSubmissions/{sub['id']}")
        sub_after = asc._attrs((doc or {}).get("data")).get("state") or sub_after
        version_after = asc.refetch_app_store_state(client, target["id"])
        if version_after not in ("WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW") and sub_after != "CANCELING":
            break
    msg = (
        f"Canceled reviewSubmission {sub['id']}: submission {sub_state} -> {sub_after}; "
        f"version {version_string} {state_before} -> {version_after}."
    )
    asc.log(msg)
    asc.write_step_summary(msg)
    return 0


def main() -> int:
    try:
        version = asc.require_env("ASC_VERSION").strip()
        dry_run = asc.parse_bool(os.environ.get("ASC_DRY_RUN"), default=True)
        key_id = asc.require_env("ASC_KEY_ID").strip()
        issuer_id = asc.require_env("ASC_ISSUER_ID").strip()
        raw_key = asc.require_env("ASC_KEY_P8")
        for s in (key_id, issuer_id, raw_key):
            asc.note_secret(s)
        pem = asc.load_p8(raw_key)
        asc.note_secret(pem)
        asc.assert_ec_key(pem)
        return run(asc.AscClient(key_id, issuer_id, pem), version, dry_run)
    except asc.AscFailure as exc:
        asc.log(f"ERROR: {exc}")
        return 1
    except Exception as exc:
        asc.log(f"ERROR: {type(exc).__name__}: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
