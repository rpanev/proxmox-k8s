#!/usr/bin/env python3
"""Remove homelab Tailscale ACL entries and delete project devices via API."""

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


def oauth_token(client_id: str, client_secret: str, scope: str) -> str:
    body = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "grant_type": "client_credentials",
            "scope": scope,
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
        eprint(f"error: OAuth token response missing access_token (scope={scope})")
        sys.exit(1)
    return token


def api_json(
    method: str,
    path: str,
    token: str,
    *,
    body: dict | None = None,
    etag: str | None = None,
    allow_404: bool = False,
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
        if allow_404 and exc.code == 404:
            return {}, {}
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


def unmerge_policy(current: dict, fragment: dict) -> dict:
    merged = copy.deepcopy(current) if current else {}

    for tag in fragment.get("tagOwners", {}):
        owners = merged.get("tagOwners", {}).get(tag)
        if tag == "tag:k8s-operator" and owners == []:
            merged.get("tagOwners", {}).pop(tag, None)
        else:
            merged.get("tagOwners", {}).pop(tag, None)

    frag_routes = fragment.get("autoApprovers", {}).get("routes", {})
    if frag_routes:
        merged.setdefault("autoApprovers", {}).setdefault("routes", {})
        for cidr, approvers in frag_routes.items():
            if cidr not in merged["autoApprovers"]["routes"]:
                continue
            remaining = [
                a
                for a in merged["autoApprovers"]["routes"][cidr]
                if a not in approvers
            ]
            if remaining:
                merged["autoApprovers"]["routes"][cidr] = remaining
            else:
                del merged["autoApprovers"]["routes"][cidr]
        if not merged["autoApprovers"]["routes"]:
            merged["autoApprovers"].pop("routes", None)
        if not merged["autoApprovers"]:
            merged.pop("autoApprovers", None)

    frag_grants = fragment.get("grants", [])
    if frag_grants:
        remove_keys = {grant_key(g) for g in frag_grants}
        merged["grants"] = [
            g for g in merged.get("grants", []) if grant_key(g) not in remove_keys
        ]
        if not merged["grants"]:
            merged.pop("grants", None)

    return merged


def device_id(device: dict) -> str | None:
    return device.get("nodeId") or device.get("id")


def should_delete_device(
    device: dict,
    *,
    proxy_tag: str,
    connector_hostname: str,
) -> bool:
    tags = set(device.get("tags") or [])
    hostname = (device.get("hostname") or device.get("name") or "").split(".")[0]

    if proxy_tag in tags:
        return True
    if connector_hostname and hostname == connector_hostname:
        return True
    if hostname == "tailscale-operator" and "tag:k8s-operator" in tags:
        return True
    return False


def remove_acl(tailnet: str, client_id: str, client_secret: str, fragment: dict) -> None:
    token = oauth_token(client_id, client_secret, "policy_file")
    current, get_headers = api_json("GET", f"/tailnet/{tailnet}/acl", token)
    etag = get_headers.get("ETag") or get_headers.get("etag")
    merged = unmerge_policy(current, fragment)
    api_json("POST", f"/tailnet/{tailnet}/acl/validate", token, body=merged)
    api_json("POST", f"/tailnet/{tailnet}/acl", token, body=merged, etag=etag)
    print(f"removed homelab ACL entries from {tailnet}")


def remove_devices(
    tailnet: str,
    client_id: str,
    client_secret: str,
    *,
    proxy_tag: str,
    connector_hostname: str,
) -> None:
    token = oauth_token(client_id, client_secret, "devices")
    payload, _ = api_json("GET", f"/tailnet/{tailnet}/devices?fields=all", token)
    devices = payload.get("devices") or []

    deleted = 0
    for device in devices:
        if not should_delete_device(
            device, proxy_tag=proxy_tag, connector_hostname=connector_hostname
        ):
            continue
        dev_id = device_id(device)
        if not dev_id:
            continue
        hostname = device.get("hostname") or device.get("name") or dev_id
        api_json("DELETE", f"/device/{dev_id}", token, allow_404=True)
        print(f"deleted device: {hostname}")
        deleted += 1

    if deleted == 0:
        print("no matching Tailscale devices found (already removed or cluster offline)")


def proxy_tag_from_fragment(fragment: dict, default: str) -> str:
    for tag in fragment.get("tagOwners", {}):
        if tag != "tag:k8s-operator":
            return tag
    return default


def main() -> int:
    tailnet = require_env("TAILSCALE_TAILNET")
    client_id = require_env("TAILSCALE_OAUTH_CLIENT_ID")
    client_secret = require_env("TAILSCALE_OAUTH_CLIENT_SECRET")
    fragment_path = os.environ.get(
        "TAILSCALE_ACL_FRAGMENT",
        os.path.join(os.environ.get("HOMELAB_ROOT", "."), "scripts/generated/tailscale-acl-fragment.json"),
    )
    connector_hostname = os.environ.get("TAILSCALE_CONNECTOR_HOSTNAME", "")

    if not os.path.isfile(fragment_path):
        eprint(f"error: missing ACL fragment {fragment_path}")
        return 1

    with open(fragment_path, encoding="utf-8") as handle:
        fragment = json.load(handle)

    proxy_tag = os.environ.get("TAILSCALE_PROXY_TAG", "").strip()
    if not proxy_tag:
        proxy_tag = proxy_tag_from_fragment(fragment, "tag:k8s-homelab")

    remove_devices(
        tailnet,
        client_id,
        client_secret,
        proxy_tag=proxy_tag,
        connector_hostname=connector_hostname,
    )
    remove_acl(tailnet, client_id, client_secret, fragment)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
