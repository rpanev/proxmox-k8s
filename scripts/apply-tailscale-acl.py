#!/usr/bin/env python3
"""Merge homelab ACL fragment into tailnet policy via Tailscale API."""

from __future__ import annotations

import copy
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API_BASE = "https://api.tailscale.com/api/v2"


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        eprint(f"error: {name} is required")
        sys.exit(1)
    return value


def oauth_token(client_id: str, client_secret: str) -> str:
    body = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "grant_type": "client_credentials",
            "scope": "policy_file",
        }
    ).encode()
    req = urllib.request.Request(
        f"{API_BASE}/oauth/token",
        data=body,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)
    token = payload.get("access_token")
    if not token:
        eprint("error: OAuth token response missing access_token")
        eprint("hint: add Policy file (read/write) scope to your OAuth client")
        sys.exit(1)
    return token


def api_json(
    method: str,
    path: str,
    token: str,
    *,
    body: dict | None = None,
    etag: str | None = None,
) -> tuple[dict, dict]:
    data = None
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if etag:
        headers["If-Match"] = etag

    req = urllib.request.Request(f"{API_BASE}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            headers_out = dict(resp.headers)
            if not raw:
                return {}, headers_out
            return json.loads(raw), headers_out
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        eprint(f"error: Tailscale API {method} {path} failed ({exc.code})")
        eprint(detail)
        sys.exit(1)


def grant_key(grant: dict) -> tuple:
    return (
        tuple(grant.get("src", [])),
        tuple(grant.get("dst", [])),
        tuple(grant.get("ip", [])),
    )


def merge_policy(current: dict, fragment: dict) -> dict:
    merged = copy.deepcopy(current) if current else {}

    if "tagOwners" in fragment:
        merged.setdefault("tagOwners", {})
        merged["tagOwners"].update(fragment["tagOwners"])

    if "autoApprovers" in fragment:
        merged.setdefault("autoApprovers", {})
        frag_aa = fragment["autoApprovers"]
        if "routes" in frag_aa:
            merged["autoApprovers"].setdefault("routes", {})
            for cidr, approvers in frag_aa["routes"].items():
                existing = merged["autoApprovers"]["routes"].get(cidr, [])
                merged["autoApprovers"]["routes"][cidr] = list(
                    dict.fromkeys([*existing, *approvers])
                )
        for key, value in frag_aa.items():
            if key != "routes":
                merged["autoApprovers"][key] = value

    if "grants" in fragment:
        merged.setdefault("grants", [])
        seen = {grant_key(g) for g in merged["grants"]}
        for grant in fragment["grants"]:
            key = grant_key(grant)
            if key not in seen:
                merged["grants"].append(grant)
                seen.add(key)

    return merged


def main() -> int:
    tailnet = require_env("TAILSCALE_TAILNET")
    client_id = require_env("TAILSCALE_OAUTH_CLIENT_ID")
    client_secret = require_env("TAILSCALE_OAUTH_CLIENT_SECRET")
    fragment_path = os.environ.get(
        "TAILSCALE_ACL_FRAGMENT",
        os.path.join(os.environ.get("HOMELAB_ROOT", "."), "scripts/generated/tailscale-acl-fragment.json"),
    )
    dry_run = os.environ.get("TAILSCALE_ACL_DRY_RUN", "").lower() in {"1", "true", "yes"}

    if not os.path.isfile(fragment_path):
        eprint(f"error: missing ACL fragment {fragment_path}")
        return 1

    with open(fragment_path, encoding="utf-8") as handle:
        fragment = json.load(handle)

    token = oauth_token(client_id, client_secret)
    current, get_headers = api_json("GET", f"/tailnet/{tailnet}/acl", token)
    etag = get_headers.get("ETag") or get_headers.get("etag")

    merged = merge_policy(current, fragment)

    api_json("POST", f"/tailnet/{tailnet}/acl/validate", token, body=merged)

    if dry_run:
        print(json.dumps(merged, indent=2))
        eprint("dry-run: ACL validated, not applied")
        return 0

    api_json("POST", f"/tailnet/{tailnet}/acl", token, body=merged, etag=etag)
    print(f"applied Tailscale ACL for {tailnet}")
    print(f"  tagOwners: {', '.join(fragment.get('tagOwners', {}).keys())}")
    routes = fragment.get("autoApprovers", {}).get("routes", {})
    for cidr, approvers in routes.items():
        print(f"  autoApprovers {cidr}: {', '.join(approvers)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
