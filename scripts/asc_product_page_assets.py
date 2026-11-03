#!/usr/bin/env python3
"""Upload and place the product page Header and Search Results images.

Uses the App Store Connect API Asset Library (API 4.5.1+):
  GET  /v1/apps/{app}/assetLibrary
  POST /v1/appAssetLibraryImages (category CREATIVE_ASSETS)
  PUT  bytes to each uploadOperations entry
  PATCH /v1/appAssetLibraryImages/{id} uploaded=true, poll until COMPLETE
  POST /v1/appAssetLibraryPlacements (PRODUCT_PAGE_HEADER_ASSET,
       APP_STORE_SEARCH_RESULTS_ASSET) on every localization of the version.

Environment:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8   same secrets as submit-review.yml
  ASC_VERSION    editable App Store version, for example 3.6.12
  ASC_DRY_RUN    true (default): read-only, prints what it would do.

Never submits for review. Secrets and the JWT are never printed.
"""

from __future__ import annotations

import hashlib
import os
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_submit_review import (  # noqa: E402
    APP_ID, EDITABLE_VERSION_STATES, AscClient, AscFailure, assert_ec_key,
    load_p8, log, note_secret, parse_bool,
)

ROOT = Path(__file__).resolve().parent.parent / "fastlane" / "product-page"
ASSETS = [
    ("PRODUCT_PAGE_HEADER_ASSET", ROOT / "header-B-3840x1646.png", "CFB Pickems header (red B)"),
    ("APP_STORE_SEARCH_RESULTS_ASSET", ROOT / "search-A-3840x2560.png", "CFB Pickems search results (red A)"),
]


def find_version(client: AscClient, version: str) -> dict:
    _, body = client.request("GET", f"/v1/apps/{APP_ID}/appStoreVersions",
                             params={"filter[platform]": "IOS", "filter[versionString]": version, "limit": 5})
    rows = (body or {}).get("data") or []
    if not rows:
        raise AscFailure(f"No iOS App Store version {version}.")
    v = rows[0]
    state = v["attributes"].get("appVersionState") or v["attributes"].get("appStoreState")
    log(f"Version {version}: {state}")
    if state not in EDITABLE_VERSION_STATES:
        raise AscFailure(f"Version {version} is {state}, not editable.")
    return v


DONE_STATES = ("COMPLETE", "READY", "PROCESSED")
POLL_SECONDS = 15
POLL_LIMIT = 40 * 60  # Apple can take 30+ minutes to process large images


def _image_state(attrs: dict) -> str | None:
    return attrs.get("state") or (attrs.get("assetDeliveryState") or {}).get("state")


def find_existing(client: AscClient, library_id: str, ref: str) -> dict | None:
    """Return the Asset Library image whose referenceName is ref, if any."""
    path = f"/v1/appAssetLibraries/{library_id}/images"
    params: dict | None = {"limit": 200}
    while path:
        _, body = client.request("GET", path, params=params, allow_status=(404,))
        for img in (body or {}).get("data") or []:
            if (img.get("attributes") or {}).get("referenceName") == ref:
                return img
        nxt = ((body or {}).get("links") or {}).get("next")
        if not nxt:
            break
        path, params = nxt.split("https://api.appstoreconnect.apple.com", 1)[-1], None
    return None


def wait_processed(client: AscClient, image_id: str, name: str) -> str:
    deadline = time.monotonic() + POLL_LIMIT
    state = None
    while True:
        _, b = client.request("GET", f"/v1/appAssetLibraryImages/{image_id}")
        a = b["data"]["attributes"]
        state = _image_state(a)
        if state in DONE_STATES:
            return state
        if state == "FAILED":
            raise AscFailure(f"{name} processing failed: {a}")
        if time.monotonic() > deadline:
            raise AscFailure(f"{name} did not finish processing in {POLL_LIMIT // 60} min (last state {state}).")
        time.sleep(POLL_SECONDS)


def upload(client: AscClient, library_id: str, path: Path, ref: str) -> str:
    data = path.read_bytes()
    existing = find_existing(client, library_id, ref)
    if existing:
        a = existing.get("attributes") or {}
        state = _image_state(a)
        same = a.get("fileSize") in (None, len(data)) and a.get("fileName") in (None, path.name)
        if same and state != "FAILED" and state not in (None, "AWAITING_UPLOAD"):
            log(f"Reusing existing image {existing['id']} for '{ref}' (state {state})")
            state = wait_processed(client, existing["id"], path.name)
            log(f"Image {existing['id']} {state}")
            return existing["id"]
        log(f"Deleting stale image {existing['id']} for '{ref}' (state {state})")
        client.request("DELETE", f"/v1/appAssetLibraryImages/{existing['id']}")
    _, body = client.request("POST", "/v1/appAssetLibraryImages", json_body={"data": {
        "type": "appAssetLibraryImages",
        "attributes": {"fileName": path.name, "fileSize": len(data),
                       "category": "CREATIVE_ASSETS", "referenceName": ref},
        "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": library_id}}},
    }})
    image = body["data"]
    for op in image["attributes"].get("uploadOperations") or []:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        r = requests.request(op.get("method", "PUT"), op["url"], data=chunk, headers=headers, timeout=120)
        if r.status_code >= 300:
            raise AscFailure(f"Upload chunk for {path.name} failed: HTTP {r.status_code}")
    client.request("PATCH", f"/v1/appAssetLibraryImages/{image['id']}", json_body={"data": {
        "type": "appAssetLibraryImages", "id": image["id"], "attributes": {"uploaded": True}}})
    state = wait_processed(client, image["id"], path.name)
    log(f"Uploaded {path.name} -> image {image['id']} ({state})")
    return image["id"]


def main() -> int:
    dry = parse_bool(os.environ.get("ASC_DRY_RUN"), True)
    version = (os.environ.get("ASC_VERSION") or "").strip()
    if not version:
        raise AscFailure("ASC_VERSION is required.")
    for _, path, _ in ASSETS:
        if not path.is_file():
            raise AscFailure(f"Missing {path}")
        log(f"{path.name}: {path.stat().st_size} bytes, sha256 {hashlib.sha256(path.read_bytes()).hexdigest()[:12]}")
    for n in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        note_secret(os.environ.get(n))
    pem = load_p8(os.environ.get("ASC_KEY_P8", ""))
    assert_ec_key(pem)
    client = AscClient(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], pem)

    _, lib = client.request("GET", f"/v1/apps/{APP_ID}/assetLibrary")
    library_id = lib["data"]["id"]
    log(f"Asset library: {library_id}")
    v = find_version(client, version)
    _, locs = client.request("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")
    locs = locs.get("data") or []
    log("Localizations: " + ", ".join(l["attributes"]["locale"] for l in locs))
    for loc in locs:
        _, pl = client.request("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/placements",
                               allow_status=(404,))
        existing = [p["attributes"].get("placementType") for p in ((pl or {}).get("data") or [])]
        log(f"  {loc['attributes']['locale']} existing placements: {existing or 'none'}")

    for _, path, ref in ASSETS:
        ex = find_existing(client, library_id, ref)
        log(f"  library image '{ref}': " + (f"{ex['id']} state {_image_state(ex.get('attributes') or {})}" if ex else "none"))

    if dry:
        log("DRY RUN: would upload 2 CREATIVE_ASSETS images and place them "
            f"({', '.join(t for t, _, _ in ASSETS)}) on {len(locs)} localization(s). Nothing changed.")
        return 0

    for ptype, path, ref in ASSETS:
        image_id = upload(client, library_id, path, ref)
        for loc in locs:
            _, pl = client.request("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/placements",
                                   params={"filter[placementType]": ptype}, allow_status=(404,))
            for old in (pl or {}).get("data") or []:
                if old["attributes"].get("placementType") == ptype:
                    client.request("DELETE", f"/v1/appAssetLibraryPlacements/{old['id']}")
                    log(f"  removed old {ptype} placement on {loc['attributes']['locale']}")
            client.request("POST", "/v1/appAssetLibraryPlacements", json_body={"data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {"placementType": ptype},
                "relationships": {
                    "image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}},
                },
            }})
            log(f"  placed {ptype} on {loc['attributes']['locale']}")
    log("Done. Not submitted for review.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AscFailure as e:
        log(f"ERROR: {e}")
        sys.exit(1)
