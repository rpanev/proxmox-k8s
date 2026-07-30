#!/usr/bin/env python3
"""Delete Cloudflare DNS records managed by external-dns for this homelab."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.cloudflare.com/client/v4"
HERITAGE = "heritage=external-dns"
OWNER_KEY = "external-dns/owner="


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        eprint(f"error: {name} is required")
        sys.exit(1)
    return value


def cf_request(
    method: str,
    path: str,
    token: str,
    *,
    body: dict | None = None,
) -> dict:
    data = None
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode()
    req = urllib.request.Request(f"{API}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        eprint(f"error: Cloudflare API {method} {path}: HTTP {exc.code}: {detail}")
        sys.exit(1)
    if not payload.get("success"):
        eprint(f"error: Cloudflare API {method} {path}: {payload.get('errors', payload)}")
        sys.exit(1)
    return payload


def zone_id(token: str, zone_name: str) -> str:
    q = urllib.parse.urlencode({"name": zone_name})
    payload = cf_request("GET", f"/zones?{q}", token)
    for zone in payload.get("result", []):
        if zone.get("name", "").lower() == zone_name.lower():
            return zone["id"]
    eprint(f"error: Cloudflare zone not found: {zone_name}")
    sys.exit(1)


def list_dns_records(token: str, zid: str) -> list[dict]:
    records: list[dict] = []
    page = 1
    while True:
        q = urllib.parse.urlencode({"per_page": "100", "page": str(page)})
        payload = cf_request("GET", f"/zones/{zid}/dns_records?{q}", token)
        batch = payload.get("result", [])
        records.extend(batch)
        info = payload.get("result_info") or {}
        if page >= info.get("total_pages", 1):
            break
        page += 1
    return records


def norm_name(name: str) -> str:
    return name.rstrip(".").lower()


def expected_hostnames() -> set[str]:
    gateway = os.environ.get("GATEWAY_DOMAIN", "").strip().lower()
    if not gateway:
        return set()
    names = {gateway, f"*.{gateway}"}
    for key, default in (
        ("ARGOCD_HOSTNAME", "argocd"),
        ("LONGHORN_HOSTNAME", "longhorn"),
        ("GRAFANA_HOSTNAME", "grafana"),
        ("PROMETHEUS_HOSTNAME", "prometheus"),
    ):
        host = os.environ.get(key, default).strip().lower() or default
        names.add(f"{host}.{gateway}")
    return names


def owned_txt_names(records: list[dict], owner: str) -> set[str]:
    names: set[str] = set()
    needle = f"{OWNER_KEY}{owner}"
    for rec in records:
        if rec.get("type") != "TXT":
            continue
        content = rec.get("content", "")
        if HERITAGE in content and needle in content:
            names.add(norm_name(rec["name"]))
    return names


def should_delete(rec: dict, owned_names: set[str], expected: set[str], lb_ip: str) -> bool:
    name = norm_name(rec["name"])
    rtype = rec.get("type", "")
    content = rec.get("content", "")

    if rtype == "TXT":
        if name in owned_names:
            return True
        if HERITAGE in content and name in expected:
            return True
        return False

    if name in owned_names and rtype in ("A", "AAAA", "CNAME"):
        return True

    if name not in expected or rtype not in ("A", "AAAA"):
        return False
    if lb_ip and rtype in ("A", "AAAA") and content != lb_ip:
        return False
    return True


def main() -> None:
    token = require_env("CLOUDFLARE_API_TOKEN")
    zone_name = require_env("EXTERNAL_DNS_ZONE")
    owner = os.environ.get("EXTERNAL_DNS_TXT_OWNER_ID", "").strip()
    if not owner:
        owner = f"homelab-{require_env('ENV_ID')}"
    lb_ip = os.environ.get("GATEWAY_LB_IP", "").strip()
    gateway = os.environ.get("GATEWAY_DOMAIN", "").strip()

    zid = zone_id(token, zone_name)
    records = list_dns_records(token, zid)
    owned_names = owned_txt_names(records, owner)
    expected = expected_hostnames()

    to_delete = [r for r in records if should_delete(r, owned_names, expected, lb_ip)]
    if not to_delete:
        print(f"no external-dns records to remove in zone {zone_name} (owner={owner})")
        if gateway:
            print(f"  (checked: {', '.join(sorted(expected))})")
        return

    print(f"removing {len(to_delete)} Cloudflare record(s) in {zone_name} (owner={owner})")
    for rec in to_delete:
        cf_request("DELETE", f"/zones/{zid}/dns_records/{rec['id']}", token)
        print(f"  deleted {rec['type']} {rec['name']} -> {rec.get('content', '')}")


if __name__ == "__main__":
    main()
