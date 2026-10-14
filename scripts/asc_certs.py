#!/usr/bin/env python3
"""List or revoke App Store Connect signing certificates (maintenance only).

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (same secrets as testflight.yml)
     ASC_CERT_MODE  list | revoke
     ASC_CERT_IDS   comma-separated certificate ids (revoke only, required)
Never prints key material, the JWT, the issuer id or certificate content.
"""
from __future__ import annotations

import os
import sys

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_submit_review import load_p8, make_token, note_secret, redact  # noqa: E402

API = "https://api.appstoreconnect.apple.com"
FIELDS = "name,displayName,certificateType,platform,expirationDate,serialNumber,activated"


def out(msg: str = "") -> None:
    print(redact(msg), flush=True)


def headers() -> dict:
    kid, iss, raw = (os.environ.get(k, "") for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"))
    if not (kid and iss and raw):
        sys.exit("Missing ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8")
    note_secret(iss)
    pem = load_p8(raw)
    return {"Authorization": f"Bearer {make_token(kid, iss, pem)}"}


def list_certs(h: dict) -> None:
    url = f"{API}/v1/certificates"
    params = {"limit": 200, "fields[certificates]": FIELDS}
    rows = []
    while url:
        r = requests.get(url, headers=h, params=params, timeout=60)
        if r.status_code != 200:
            sys.exit(f"GET certificates failed {r.status_code}: {redact(r.text)[:2000]}")
        doc = r.json()
        rows += doc.get("data", [])
        url, params = (doc.get("links") or {}).get("next"), None
    out(f"{len(rows)} certificates")
    out("id | name | displayName | certificateType | platform | expirationDate | serialNumber | activated")
    for c in sorted(rows, key=lambda c: (c["attributes"].get("certificateType") or "", c["attributes"].get("expirationDate") or "")):
        a = c.get("attributes") or {}
        out(" | ".join(str(x) for x in (c["id"], a.get("name"), a.get("displayName"), a.get("certificateType"),
                                        a.get("platform"), a.get("expirationDate"), a.get("serialNumber"), a.get("activated"))))
    out("(Apple sets expirationDate one year after creation, so created ~= expirationDate - 1y.)")


def revoke(h: dict, ids: list[str]) -> int:
    bad = 0
    for cid in ids:
        r = requests.get(f"{API}/v1/certificates/{cid}", headers=h, params={"fields[certificates]": FIELDS}, timeout=60)
        if r.status_code != 200:
            out(f"{cid}: lookup failed {r.status_code}: {redact(r.text)[:500]}")
            bad += 1
            continue
        a = r.json()["data"]["attributes"]
        ctype = a.get("certificateType") or ""
        if "DISTRIBUTION" in ctype or ctype not in {"DEVELOPMENT", "IOS_DEVELOPMENT", "APPLE_DEVELOPMENT"}:
            out(f"{cid}: REFUSING to revoke type {ctype} ({a.get('name')})")
            bad += 1
            continue
        d = requests.delete(f"{API}/v1/certificates/{cid}", headers=h, timeout=60)
        out(f"{cid} {ctype} {a.get('name')} / {a.get('displayName')} exp {a.get('expirationDate')}: DELETE -> {d.status_code}"
            + ("" if d.status_code == 204 else f" {redact(d.text)[:500]}"))
        bad += d.status_code != 204
    return 1 if bad else 0


def main() -> int:
    mode = (os.environ.get("ASC_CERT_MODE") or "list").strip()
    h = headers()
    if mode == "list":
        list_certs(h)
        return 0
    if mode == "revoke":
        ids = [i.strip() for i in (os.environ.get("ASC_CERT_IDS") or "").split(",") if i.strip()]
        if not ids:
            sys.exit("revoke needs explicit ids")
        rc = revoke(h, ids)
        list_certs(h)
        return rc
    sys.exit(f"unknown mode {mode}")


if __name__ == "__main__":
    sys.exit(main())
