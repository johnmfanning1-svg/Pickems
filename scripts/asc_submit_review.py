#!/usr/bin/env python3
"""Submit an already-uploaded Pickems iOS build for App Store review.

Uses the App Store Connect API. The TestFlight workflow stays upload-only;
this script never archives or uploads a binary.

Dependencies (installed by .github/workflows/submit-review.yml):
  PyJWT, cryptography, requests

Environment:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8   same secrets as testflight.yml
  ASC_VERSION    marketing version, for example 3.6.1
  ASC_BUILD      build number already uploaded, for example 10007
  WHATS_NEW      What's New text for every localization
  ASC_DRY_RUN    true (default) or false

The key, the JWT, and the issuer id are never printed.
"""

from __future__ import annotations

import base64
import os
import re
import sys
import time
from typing import Any, Callable

import jwt
import requests
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import load_pem_private_key

API_ROOT = "https://api.appstoreconnect.apple.com"
APP_ID = "6785697079"
BUNDLE_ID = "FannypackInc.Pickems"
PLATFORM = "IOS"
TOKEN_AUD = "appstoreconnect-v1"
TOKEN_TTL_SECONDS = 20 * 60
POLL_INTERVAL_SECONDS = 60
POLL_TIMEOUT_SECONDS = 30 * 60
STATE_CONFIRM_ATTEMPTS = 6
STATE_CONFIRM_INTERVAL_SECONDS = 10
WHATS_NEW_LIMIT = 4000

EDITABLE_VERSION_STATES = frozenset({
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
    "WAITING_FOR_EXPORT_COMPLIANCE",
})

# States that occupy the single open iOS version slot. Historical REJECTED
# versions are left out so an old rejection cannot block a new version;
# Apple still rejects the create, and that detail is what we print.
BLOCKING_CREATE_STATES = frozenset({
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
    "WAITING_FOR_EXPORT_COMPLIANCE",
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_APPLE_RELEASE",
    "PENDING_DEVELOPER_RELEASE",
    "PROCESSING_FOR_DISTRIBUTION",
})

OPEN_SUBMISSION_STATES = frozenset({
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "UNRESOLVED_ISSUES",
})

REQUIRED_LOCALIZATION_FIELDS = ("description", "keywords", "supportUrl")
TERMINAL_BUILD_FAILURES = frozenset({"FAILED", "INVALID"})

_PEM_RE = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
    re.DOTALL,
)
_JWT_RE = re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b")
_SENSITIVE: list[str] = []


class AscFailure(Exception):
    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


def note_secret(value: str | None) -> None:
    if value and len(value) >= 8:
        _SENSITIVE.append(value)


def redact(text: str, secrets: list[str] | None = None) -> str:
    """Strip key material, JWTs, and any registered secret from text we print."""
    redacted = _PEM_RE.sub("[REDACTED KEY]", text or "")
    redacted = _JWT_RE.sub("[REDACTED TOKEN]", redacted)
    pool = list(secrets or []) + list(_SENSITIVE)
    for secret in sorted({s for s in pool if s and len(s) >= 8}, key=len, reverse=True):
        redacted = redacted.replace(secret, "[REDACTED]")
    return redacted


def log(message: str = "") -> None:
    print(redact(message), flush=True)


def version_sort_key(version_string: str) -> tuple:
    parts: list[int] = []
    for piece in (version_string or "").split("."):
        try:
            parts.append(int(piece))
        except ValueError:
            parts.append(-1)
    return tuple(parts)


def _attrs(resource: dict | None) -> dict:
    if not resource:
        return {}
    return resource.get("attributes") or {}


def _is_ios(resource: dict) -> bool:
    platform = _attrs(resource).get("platform")
    return platform in (None, PLATFORM)


def pick_live_version(versions: list[dict]) -> dict | None:
    """The iOS version currently READY_FOR_SALE. Highest version string wins."""
    live = [
        version for version in versions
        if _is_ios(version) and _attrs(version).get("appStoreState") == "READY_FOR_SALE"
    ]
    if not live:
        return None
    return max(
        live,
        key=lambda version: (
            version_sort_key(_attrs(version).get("versionString") or ""),
            _attrs(version).get("createdDate") or "",
        ),
    )


def pick_reusable_version(versions: list[dict], version_string: str) -> dict | None:
    """Editable iOS appStoreVersion with this versionString, or None if absent.

    Raises AscFailure when that version exists but is not in an editable state.
    """
    matches = [
        version for version in versions
        if _is_ios(version) and _attrs(version).get("versionString") == version_string
    ]
    if not matches:
        return None
    editable = [
        version for version in matches
        if _attrs(version).get("appStoreState") in EDITABLE_VERSION_STATES
    ]
    if editable:
        return editable[0]
    states = ", ".join(
        f"{version.get('id')} ({_attrs(version).get('appStoreState')})"
        for version in matches
    )
    raise AscFailure(
        f"iOS version {version_string} already exists but is not editable: {states}. "
        "Refusing to modify it."
    )


def blocking_version(versions: list[dict], version_string: str) -> dict | None:
    """Another open iOS version that would stop us creating version_string."""
    for version in versions:
        if not _is_ios(version):
            continue
        attrs = _attrs(version)
        if attrs.get("versionString") == version_string:
            continue
        if attrs.get("appStoreState") in BLOCKING_CREATE_STATES:
            return version
    return None


def select_build(builds: list[dict]) -> dict:
    """Non-expired build, preferring VALID, then the latest upload."""
    if not builds:
        raise AscFailure("No matching build.")
    fresh = [build for build in builds if not _attrs(build).get("expired")]
    if not fresh:
        raise AscFailure("Matching builds are expired.")

    def rank(build: dict) -> tuple:
        attrs = _attrs(build)
        return (attrs.get("processingState") == "VALID", attrs.get("uploadedDate") or "")

    return max(fresh, key=rank)


def builds_from_payload(payload: dict, version_string: str, build_number: str) -> list[dict]:
    """Keep builds whose CFBundleVersion matches and whose train matches, when included."""
    included = {
        (item.get("type"), item.get("id")): item
        for item in payload.get("included") or []
    }
    matched: list[dict] = []
    for build in payload.get("data") or []:
        attrs = _attrs(build)
        if str(attrs.get("version")) != str(build_number):
            continue
        rel = ((build.get("relationships") or {}).get("preReleaseVersion") or {}).get("data") or {}
        pre = included.get((rel.get("type"), rel.get("id")))
        if pre is not None:
            pre_version = _attrs(pre).get("version")
            pre_platform = _attrs(pre).get("platform")
            if pre_version != version_string:
                continue
            if pre_platform not in (None, PLATFORM):
                continue
        matched.append(build)
    return matched


def encryption_to_set(current: Any, live_value: Any) -> tuple[bool | None, str]:
    """Value to PATCH onto usesNonExemptEncryption, or None when it is already set.

    Null on the target copies the live build's flag, or false when that is unknown.
    """
    if current is not None:
        return None, "already set"
    if live_value is not None:
        return bool(live_value), "copied from the READY_FOR_SALE build"
    return False, "defaulted to false"


def localization_patch(target_attrs: dict, live_attrs: dict | None, whats_new: str) -> dict:
    """whatsNew for this locale, plus any empty required field copied from live."""
    patch = {"whatsNew": whats_new}
    live = live_attrs or {}
    for field in REQUIRED_LOCALIZATION_FIELDS:
        if not str(target_attrs.get(field) or "").strip():
            copied = str(live.get(field) or "").strip()
            if copied:
                patch[field] = copied
    return patch


def missing_required_fields(attrs: dict) -> list[str]:
    return [
        field for field in REQUIRED_LOCALIZATION_FIELDS
        if not str((attrs or {}).get(field) or "").strip()
    ]


def pick_open_review_submission(submissions: list[dict]) -> dict | None:
    """An unsubmitted READY_FOR_REVIEW submission we can add this version to."""
    ready = []
    for submission in submissions:
        attrs = _attrs(submission)
        if attrs.get("state") != "READY_FOR_REVIEW":
            continue
        if attrs.get("platform") not in (None, PLATFORM):
            continue
        ready.append(submission)
    if not ready:
        return None
    return max(ready, key=lambda submission: _attrs(submission).get("createdDate") or "")


def blocking_review_submission(submissions: list[dict]) -> dict | None:
    for submission in submissions:
        attrs = _attrs(submission)
        if attrs.get("platform") not in (None, PLATFORM):
            continue
        if attrs.get("state") in OPEN_SUBMISSION_STATES:
            return submission
    return None


def submission_includes_version(items: list[dict], version_id: str) -> bool:
    for item in items:
        rel = ((item.get("relationships") or {}).get("appStoreVersion") or {}).get("data") or {}
        if rel.get("id") == version_id:
            return True
    return False


def idfa_status_from_response(status: int, body: dict | None) -> str:
    """Whether the live version's IDFA declaration resource exists. Read-only."""
    if status == 200 and isinstance(body, dict) and body.get("data"):
        return "present"
    if status == 404 or (status == 200 and isinstance(body, dict) and not body.get("data")):
        return "absent"
    return "not readable"


def api_error_message(method: str, path: str, status: int, payload: Any) -> str:
    """Readable failure that includes each errors[].detail."""
    path_only = path.split("?", 1)[0]
    details: list[str] = []
    if isinstance(payload, dict):
        for err in payload.get("errors") or []:
            if not isinstance(err, dict):
                continue
            detail = str(err.get("detail") or "").strip()
            title = str(err.get("title") or "").strip()
            code = str(err.get("code") or "").strip()
            if detail and title and detail != title:
                text = f"{title}: {detail}"
            else:
                text = detail or title
            if code and text:
                text = f"{code}: {text}"
            elif code:
                text = code
            if text:
                details.append(text)
    prefix = f"{method} {path_only} failed ({status})"
    if details:
        return prefix + ": " + "; ".join(details)
    return prefix


def token_claims(issuer_id: str, now: int) -> dict:
    return {
        "iss": issuer_id,
        "iat": now,
        "exp": now + TOKEN_TTL_SECONDS,
        "aud": TOKEN_AUD,
    }


def load_p8(raw: str) -> str:
    """PEM private key, accepting the raw PEM or base64 used by testflight.yml."""
    if raw is None or not str(raw).strip():
        raise AscFailure("ASC_KEY_P8 is empty.")
    text = str(raw).strip()
    if "-----BEGIN PRIVATE KEY-----" in text:
        text = text.replace("\\n", "\n")
    else:
        compact = re.sub(r"\s+", "", text)
        try:
            decoded = base64.b64decode(compact, validate=True)
            text = decoded.decode("utf-8")
        except Exception:
            raise AscFailure("ASC_KEY_P8 is neither a PEM .p8 nor base64 of one.")
    if not text.endswith("\n"):
        text += "\n"
    if "-----BEGIN PRIVATE KEY-----" not in text or "-----END PRIVATE KEY-----" not in text:
        raise AscFailure("ASC_KEY_P8 is neither a PEM .p8 nor base64 of one.")
    return text


def assert_ec_key(pem: str) -> None:
    try:
        key = load_pem_private_key(pem.encode("utf-8"), password=None)
    except Exception:
        raise AscFailure("ASC_KEY_P8 could not be parsed as a private key.")
    if not isinstance(key, ec.EllipticCurvePrivateKey):
        raise AscFailure("ASC_KEY_P8 is not an EC private key (ES256 requires a P-256 key).")


def make_token(key_id: str, issuer_id: str, pem: str, now: int | None = None) -> str:
    issued = int(time.time() if now is None else now)
    token = jwt.encode(
        token_claims(issuer_id, issued),
        pem,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )
    if isinstance(token, bytes):
        token = token.decode("ascii")
    return token


def parse_bool(value: str | None, default: bool = True) -> bool:
    if value is None or str(value).strip() == "":
        return default
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes"}:
        return True
    if normalized in {"0", "false", "no"}:
        return False
    raise AscFailure(f"dry_run must be true or false (got {value!r}).")


def format_summary(info: dict) -> str:
    locales = info.get("locales") or []
    locale_text = ", ".join(locales) if locales else "(none)"
    lines = [
        "App Store review",
        f"App: {info.get('bundle_id')} ({info.get('app_id')}) {info.get('platform')}",
        (
            f"Build {info.get('build_number')} id={info.get('build_id')} "
            f"processingState={info.get('processing_state')} "
            f"usesNonExemptEncryption={info.get('encryption')} ({info.get('encryption_note')})"
        ),
        (
            f"Version {info.get('version_string')} id={info.get('version_id')} "
            f"appStoreState={info.get('version_state')} "
            f"releaseType={info.get('release_type')} ({info.get('release_note')})"
        ),
        f"Attached build id={info.get('attached_build_id')}",
        f"Locales updated: {locale_text}",
        (
            f"Live version {info.get('live_version_string') or '(none)'} "
            f"id={info.get('live_version_id') or '(none)'} "
            f"IDFA/ad declaration: {info.get('idfa')}"
        ),
    ]
    for note in info.get("locale_notes") or []:
        lines.append(f"  {note}")
    if info.get("dry_run"):
        lines.append("Dry run: stopped before creating a review submission.")
    else:
        reused = "reused" if info.get("submission_reused") else "created"
        lines.append(
            f"Review submission id={info.get('submission_id')} ({reused}) "
            f"state={info.get('submission_state')}"
        )
        lines.append(
            f"Version appStoreState after submit: {info.get('version_state_after')}"
        )
    return "\n".join(lines)


class AscClient:
    def __init__(self, key_id: str, issuer_id: str, pem: str):
        self._key_id = key_id
        self._issuer_id = issuer_id
        self._pem = pem
        self._token: str | None = None
        self._exp = 0
        self._session = requests.Session()

    def _bearer(self) -> str:
        now = int(time.time())
        if self._token is None or now >= self._exp - 60:
            self._exp = now + TOKEN_TTL_SECONDS
            self._token = make_token(self._key_id, self._issuer_id, self._pem, now)
            note_secret(self._token)
        return self._token

    def request(
        self,
        method: str,
        path: str,
        *,
        json_body: dict | None = None,
        params: dict | None = None,
        allow_status: tuple[int, ...] = (),
        retry_auth: bool = True,
    ) -> tuple[int, dict | None]:
        url = path if path.startswith("https://") else API_ROOT + path
        attempts = 0
        while True:
            attempts += 1
            response = self._session.request(
                method,
                url,
                headers={
                    "Authorization": f"Bearer {self._bearer()}",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                    "User-Agent": "pickems-asc-submit",
                },
                json=json_body,
                params=params,
                timeout=60,
            )
            if response.status_code == 401 and retry_auth:
                self._token = None
                return self.request(
                    method,
                    path,
                    json_body=json_body,
                    params=params,
                    allow_status=allow_status,
                    retry_auth=False,
                )
            if response.status_code == 429 and attempts < 4:
                try:
                    delay = int(response.headers.get("Retry-After") or "5")
                except ValueError:
                    delay = 5
                delay = min(max(delay, 1), 60)
                log(f"{method} {path.split('?', 1)[0]} returned 429; retrying in {delay}s.")
                time.sleep(delay)
                continue
            break

        status = response.status_code
        body: dict | None = None
        if response.content:
            try:
                parsed = response.json()
            except ValueError:
                parsed = None
            if isinstance(parsed, dict):
                body = parsed
        if status in allow_status:
            return status, body
        if status >= 400:
            snippet = None if body is not None else (response.text or "")[:300]
            message = api_error_message(method, path, status, body)
            if snippet and not body:
                message = f"{message}: {snippet}"
            raise AscFailure(redact(message), status=status)
        return status, body

    def get_pages(self, path: str, params: dict | None = None) -> list[dict]:
        items: list[dict] = []
        next_path: str | None = path
        next_params = params
        pages = 0
        while next_path:
            pages += 1
            if pages > 20:
                raise AscFailure(f"Stopped paging {path.split('?', 1)[0]} after 20 pages.")
            _, body = self.request("GET", next_path, params=next_params)
            body = body or {}
            items.extend(body.get("data") or [])
            # Included resources from the first page are attached by the caller
            # when it uses get_document instead of get_pages.
            next_path = ((body.get("links") or {}).get("next")) or None
            next_params = None
        return items

    def get_document(self, path: str, params: dict | None = None) -> dict:
        _, body = self.request("GET", path, params=params)
        return body or {}


def list_versions(client: AscClient) -> list[dict]:
    return client.get_pages(
        f"/v1/apps/{APP_ID}/appStoreVersions",
        {"filter[platform]": PLATFORM, "limit": "200"},
    )


def find_builds(client: AscClient, version_string: str, build_number: str) -> list[dict]:
    payload = client.get_document(
        "/v1/builds",
        {
            "filter[app]": APP_ID,
            "filter[version]": build_number,
            "filter[preReleaseVersion.version]": version_string,
            "filter[preReleaseVersion.platform]": PLATFORM,
            "include": "preReleaseVersion",
            "limit": "20",
        },
    )
    return builds_from_payload(payload, version_string, build_number)


def wait_until_valid(
    fetch: Callable[[], dict],
    build_number: str,
    build_id: str,
    *,
    sleep: Callable[[float], None] = time.sleep,
    monotonic: Callable[[], float] = time.monotonic,
    interval: int = POLL_INTERVAL_SECONDS,
    timeout: int = POLL_TIMEOUT_SECONDS,
) -> dict:
    deadline = monotonic() + timeout
    while True:
        build = fetch()
        state = _attrs(build).get("processingState")
        log(f"Build {build_number} id={build_id} processingState={state}")
        if state == "VALID":
            return build
        if state in TERMINAL_BUILD_FAILURES:
            raise AscFailure(
                f"Build {build_number} id={build_id} processingState is {state}."
            )
        remaining = deadline - monotonic()
        if remaining <= 0:
            raise AscFailure(
                f"Build {build_number} id={build_id} still {state} after {timeout // 60} minutes."
            )
        delay = min(interval, remaining)
        log(f"Next processingState check in {int(delay)}s.")
        sleep(delay)


def version_build(client: AscClient, version_id: str) -> dict | None:
    status, body = client.request(
        "GET",
        f"/v1/appStoreVersions/{version_id}/build",
        allow_status=(404,),
    )
    if status == 404 or not body or not body.get("data"):
        return None
    return body["data"]


def read_idfa(client: AscClient, live: dict | None) -> str:
    """Report the live version's IDFA declaration. Never modifies it."""
    if not live:
        return "absent"
    version_id = live.get("id")
    related = (
        ((live.get("relationships") or {}).get("idfaDeclaration") or {})
        .get("links", {})
        .get("related")
    )
    path = related or f"/v1/appStoreVersions/{version_id}/idfaDeclaration"
    try:
        status, body = client.request("GET", path, allow_status=(404, 403, 400))
    except AscFailure as exc:
        return f"not readable ({exc})"
    status_text = idfa_status_from_response(status, body)
    if status_text == "not readable":
        detail = api_error_message("GET", path, status, body)
        return f"not readable ({detail})"
    return status_text


def ensure_release_type(client: AscClient, version: dict, live: dict | None) -> tuple[dict, str]:
    current = _attrs(version).get("releaseType")
    if not live:
        return version, "left unchanged; no READY_FOR_SALE version to copy from"
    wanted = _attrs(live).get("releaseType")
    if not wanted:
        return version, "left unchanged; READY_FOR_SALE version has no releaseType"
    dates_match = _attrs(version).get("earliestReleaseDate") == _attrs(live).get("earliestReleaseDate")
    if current == wanted and (wanted != "SCHEDULED" or dates_match):
        return version, f"already {wanted}, matching the READY_FOR_SALE version"
    attributes: dict[str, Any] = {"releaseType": wanted}
    if wanted == "SCHEDULED" and _attrs(live).get("earliestReleaseDate"):
        attributes["earliestReleaseDate"] = _attrs(live)["earliestReleaseDate"]
    _, body = client.request(
        "PATCH",
        f"/v1/appStoreVersions/{version['id']}",
        json_body={
            "data": {
                "type": "appStoreVersions",
                "id": version["id"],
                "attributes": attributes,
            }
        },
    )
    updated = (body or {}).get("data") or version
    return updated, f"copied {wanted} from the READY_FOR_SALE version"


def create_version(client: AscClient, version_string: str, live: dict | None) -> dict:
    if not live or not _attrs(live).get("releaseType"):
        raise AscFailure(
            f"No READY_FOR_SALE iOS version to copy releaseType from. "
            f"Refusing to create {version_string}."
        )
    attributes: dict[str, Any] = {
        "platform": PLATFORM,
        "versionString": version_string,
        "releaseType": _attrs(live)["releaseType"],
    }
    if attributes["releaseType"] == "SCHEDULED" and _attrs(live).get("earliestReleaseDate"):
        attributes["earliestReleaseDate"] = _attrs(live)["earliestReleaseDate"]
    _, body = client.request(
        "POST",
        "/v1/appStoreVersions",
        json_body={
            "data": {
                "type": "appStoreVersions",
                "attributes": attributes,
                "relationships": {
                    "app": {"data": {"type": "apps", "id": APP_ID}},
                },
            }
        },
    )
    created = (body or {}).get("data")
    if not created:
        raise AscFailure(f"Creating appStoreVersion {version_string} returned no resource.")
    log(
        f"Created appStoreVersion {version_string} id={created.get('id')} "
        f"releaseType={attributes['releaseType']}"
    )
    return created


def attach_build(client: AscClient, version_id: str, build_id: str) -> None:
    client.request(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}/relationships/build",
        json_body={"data": {"type": "builds", "id": build_id}},
    )


def list_localizations(client: AscClient, version_id: str) -> list[dict]:
    return client.get_pages(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
        {"limit": "200"},
    )


def update_localizations(
    client: AscClient,
    version_id: str,
    live: dict | None,
    whats_new: str,
) -> tuple[list[str], list[str]]:
    target = list_localizations(client, version_id)
    live_locs = list_localizations(client, live["id"]) if live else []
    live_by_locale = {_attrs(loc).get("locale"): loc for loc in live_locs}

    if not target:
        if not live_locs:
            raise AscFailure(
                f"appStoreVersion {version_id} has no localizations, and the live version "
                "has none to copy required fields from."
            )
        for loc in live_locs:
            locale = _attrs(loc).get("locale")
            attributes = localization_patch({}, _attrs(loc), whats_new)
            attributes["locale"] = locale
            _, body = client.request(
                "POST",
                "/v1/appStoreVersionLocalizations",
                json_body={
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "attributes": attributes,
                        "relationships": {
                            "appStoreVersion": {
                                "data": {"type": "appStoreVersions", "id": version_id},
                            }
                        },
                    }
                },
            )
            created = (body or {}).get("data") or {}
            if not created.get("id"):
                raise AscFailure(f"Creating the {locale} localization returned no id.")
            target.append(created)
            log(f"Created {locale} localization on {version_id}.")

    locales: list[str] = []
    notes: list[str] = []
    for loc in target:
        locale = _attrs(loc).get("locale") or loc.get("id")
        live_attrs = _attrs(live_by_locale.get(_attrs(loc).get("locale")))
        patch = localization_patch(_attrs(loc), live_attrs, whats_new)
        _, body = client.request(
            "PATCH",
            f"/v1/appStoreVersionLocalizations/{loc['id']}",
            json_body={
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc["id"],
                    "attributes": patch,
                }
            },
        )
        updated = _attrs((body or {}).get("data"))
        copied = [field for field in REQUIRED_LOCALIZATION_FIELDS if field in patch]
        extra = f" copied {', '.join(copied)}" if copied else ""
        notes.append(f"{locale}: whatsNew set.{extra}")
        # The PATCH response may omit unchanged attributes. Fields we sent and
        # fields that were already present both count as filled.
        present = dict(_attrs(loc))
        present.update(patch)
        for field, value in updated.items():
            if value:
                present[field] = value
        still_missing = missing_required_fields(present)
        if still_missing:
            raise AscFailure(
                f"Locale {locale} is missing required field(s): {', '.join(still_missing)}. "
                "The live version has nothing to copy for "
                + ("that locale." if not live_attrs else "those fields.")
            )
        locales.append(str(locale))
    return locales, notes


def list_review_submissions(client: AscClient) -> list[dict]:
    return client.get_pages(
        f"/v1/apps/{APP_ID}/reviewSubmissions",
        {"filter[platform]": PLATFORM, "limit": "50"},
    )


def submission_items(client: AscClient, submission_id: str) -> list[dict]:
    payload = client.get_document(
        f"/v1/reviewSubmissions/{submission_id}/items",
        {"include": "appStoreVersion", "limit": "50"},
    )
    items = payload.get("data") or []
    for item in items:
        rel = ((item.get("relationships") or {}).get("appStoreVersion") or {}).get("data") or {}
        if rel.get("id"):
            continue
        status, body = client.request(
            "GET",
            f"/v1/reviewSubmissionItems/{item['id']}/relationships/appStoreVersion",
            allow_status=(404,),
        )
        if status == 200 and body and body.get("data"):
            item.setdefault("relationships", {}).setdefault("appStoreVersion", {})["data"] = body["data"]
    return items


def submit_for_review(client: AscClient, version_id: str) -> tuple[dict, bool]:
    submissions = list_review_submissions(client)
    blocking = blocking_review_submission(submissions)
    if blocking:
        attrs = _attrs(blocking)
        raise AscFailure(
            f"Review submission {blocking.get('id')} is already {attrs.get('state')}. "
            "Refusing to open another submission."
        )
    existing = pick_open_review_submission(submissions)
    reused = existing is not None
    if existing:
        submission = existing
        log(f"Reusing READY_FOR_REVIEW review submission {submission.get('id')}.")
    else:
        _, body = client.request(
            "POST",
            "/v1/reviewSubmissions",
            json_body={
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": PLATFORM},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": APP_ID}},
                    },
                }
            },
        )
        submission = (body or {}).get("data")
        if not submission:
            raise AscFailure("Creating the review submission returned no resource.")
        log(f"Created review submission {submission.get('id')}.")

    submission_id = submission["id"]
    items = submission_items(client, submission_id)
    if submission_includes_version(items, version_id):
        log(f"Review submission {submission_id} already includes version {version_id}.")
    else:
        client.request(
            "POST",
            "/v1/reviewSubmissionItems",
            json_body={
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {
                            "data": {"type": "reviewSubmissions", "id": submission_id},
                        },
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id},
                        },
                    },
                }
            },
        )
        log(f"Added version {version_id} to review submission {submission_id}.")

    _, body = client.request(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        json_body={
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    submitted = (body or {}).get("data") or submission
    return submitted, reused


def refetch_app_store_state(
    client: AscClient,
    version_id: str,
    *,
    sleep: Callable[[float], None] = time.sleep,
) -> str:
    state = ""
    for attempt in range(1, STATE_CONFIRM_ATTEMPTS + 1):
        _, body = client.request("GET", f"/v1/appStoreVersions/{version_id}")
        state = _attrs((body or {}).get("data")).get("appStoreState") or ""
        log(f"appStoreVersion {version_id} appStoreState={state}")
        if state == "WAITING_FOR_REVIEW":
            return state
        if attempt < STATE_CONFIRM_ATTEMPTS:
            sleep(STATE_CONFIRM_INTERVAL_SECONDS)
    return state


def write_step_summary(text: str) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        handle.write("```\n")
        handle.write(text)
        handle.write("\n```\n")


def require_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value.strip():
        raise AscFailure(f"Missing {name}.")
    return value


def validate_inputs() -> tuple[str, str, str, bool]:
    version = os.environ.get("ASC_VERSION", "").strip()
    build = os.environ.get("ASC_BUILD", "").strip()
    whats_new = os.environ.get("WHATS_NEW", "").strip()
    dry_run = parse_bool(os.environ.get("ASC_DRY_RUN"), default=True)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise AscFailure(f"version must look like 3.6.1 (got {version!r}).")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise AscFailure(f"build must be a positive integer (got {build!r}).")
    if not whats_new:
        raise AscFailure("whats_new is empty.")
    if len(whats_new) > WHATS_NEW_LIMIT:
        raise AscFailure(
            f"whats_new is {len(whats_new)} characters; App Store Connect allows {WHATS_NEW_LIMIT}."
        )
    return version, build, whats_new, dry_run


def run(client: AscClient, version: str, build_number: str, whats_new: str, dry_run: bool) -> int:
    _, app_body = client.request("GET", f"/v1/apps/{APP_ID}")
    app = (app_body or {}).get("data") or {}
    bundle = _attrs(app).get("bundleId")
    if bundle != BUNDLE_ID:
        raise AscFailure(
            f"App {APP_ID} bundle id is {bundle!r}, expected {BUNDLE_ID}."
        )
    log(f"App {bundle} ({APP_ID}) {PLATFORM}, version {version} build {build_number}, dry_run={dry_run}")

    builds = find_builds(client, version, build_number)
    if not builds:
        raise AscFailure(
            f"No iOS build found for version {version} build {build_number} on app {APP_ID}."
        )
    chosen = select_build(builds)
    build_id = chosen["id"]

    def fetch_build() -> dict:
        _, body = client.request("GET", f"/v1/builds/{build_id}")
        data = (body or {}).get("data")
        if not data:
            raise AscFailure(f"Build {build_id} disappeared while waiting.")
        return data

    ready = wait_until_valid(fetch_build, build_number, build_id)

    versions = list_versions(client)
    live = pick_live_version(versions)
    live_build = version_build(client, live["id"]) if live else None
    new_flag, encryption_note = encryption_to_set(
        _attrs(ready).get("usesNonExemptEncryption"),
        _attrs(live_build).get("usesNonExemptEncryption") if live_build else None,
    )
    if new_flag is not None:
        log(
            f"Setting usesNonExemptEncryption={new_flag} on build {build_id} ({encryption_note}). "
            "Apple does not allow changing this later."
        )
        client.request(
            "PATCH",
            f"/v1/builds/{build_id}",
            json_body={
                "data": {
                    "type": "builds",
                    "id": build_id,
                    "attributes": {"usesNonExemptEncryption": new_flag},
                }
            },
        )
        ready = fetch_build()
    encryption_value = _attrs(ready).get("usesNonExemptEncryption")
    if encryption_value is None and new_flag is not None:
        encryption_value = new_flag

    target = pick_reusable_version(versions, version)
    if target is None:
        blocker = blocking_version(versions, version)
        if blocker:
            raise AscFailure(
                f"iOS version {_attrs(blocker).get('versionString')} id={blocker.get('id')} "
                f"is {_attrs(blocker).get('appStoreState')}. "
                f"Refusing to create {version} while that version is open."
            )
        target = create_version(client, version, live)
        copied_release = _attrs(live).get("releaseType") if live else None
        release_note = f"copied {copied_release} from the READY_FOR_SALE version"
    else:
        log(
            f"Reusing appStoreVersion {version} id={target.get('id')} "
            f"appStoreState={_attrs(target).get('appStoreState')}"
        )
        target, release_note = ensure_release_type(client, target, live)

    attach_build(client, target["id"], build_id)
    attached_id = None
    for attempt in range(3):
        attached = version_build(client, target["id"])
        attached_id = (attached or {}).get("id")
        if attached_id == build_id:
            break
        if attempt < 2:
            time.sleep(2)
    if attached_id != build_id:
        raise AscFailure(
            f"Build attach did not stick: version {target['id']} build is {attached_id}, "
            f"expected {build_id}."
        )

    locales, locale_notes = update_localizations(client, target["id"], live, whats_new)
    idfa = read_idfa(client, live)

    summary = {
        "bundle_id": BUNDLE_ID,
        "app_id": APP_ID,
        "platform": PLATFORM,
        "build_number": build_number,
        "build_id": build_id,
        "processing_state": _attrs(ready).get("processingState"),
        "encryption": encryption_value,
        "encryption_note": encryption_note,
        "version_string": version,
        "version_id": target.get("id"),
        "version_state": _attrs(target).get("appStoreState"),
        "release_type": _attrs(target).get("releaseType"),
        "release_note": release_note,
        "attached_build_id": attached_id,
        "locales": locales,
        "locale_notes": locale_notes,
        "live_version_string": _attrs(live).get("versionString") if live else None,
        "live_version_id": live.get("id") if live else None,
        "idfa": idfa,
        "dry_run": dry_run,
    }

    if dry_run:
        text = format_summary(summary)
        log(text)
        write_step_summary(text)
        return 0

    submitted, reused = submit_for_review(client, target["id"])
    state_after = refetch_app_store_state(client, target["id"])
    summary.update({
        "dry_run": False,
        "submission_id": submitted.get("id"),
        "submission_reused": reused,
        "submission_state": _attrs(submitted).get("state"),
        "version_state_after": state_after,
    })
    text = format_summary(summary)
    log(text)
    write_step_summary(text)
    if state_after != "WAITING_FOR_REVIEW":
        raise AscFailure(
            f"Expected appStoreState WAITING_FOR_REVIEW after submit, got {state_after or 'unknown'}."
        )
    return 0


def main() -> int:
    try:
        version, build_number, whats_new, dry_run = validate_inputs()
        key_id = require_env("ASC_KEY_ID").strip()
        issuer_id = require_env("ASC_ISSUER_ID").strip()
        raw_key = require_env("ASC_KEY_P8")
        note_secret(key_id)
        note_secret(issuer_id)
        note_secret(raw_key)
        pem = load_p8(raw_key)
        note_secret(pem)
        assert_ec_key(pem)
        client = AscClient(key_id, issuer_id, pem)
        return run(client, version, build_number, whats_new, dry_run)
    except AscFailure as exc:
        log(f"ERROR: {exc}")
        return 1
    except Exception as exc:
        log(f"ERROR: {type(exc).__name__}: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
