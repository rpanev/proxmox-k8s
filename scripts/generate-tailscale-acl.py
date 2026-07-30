#!/usr/bin/env python3
"""Build Tailscale ACL fragment from terraform output JSON (stdin)."""

from __future__ import annotations

import json
import sys


def main() -> int:
    data = json.load(sys.stdin)
    tailscale = data.get("tailscale", {}).get("value")
    if not tailscale:
        print("error: tailscale output missing in terraform state", file=sys.stderr)
        return 1

    proxy_tag = tailscale["proxy_tag"]
    homelab_cidr = tailscale["homelab_network_cidr"]

    policy = {
        "tagOwners": {
            "tag:k8s-operator": [],
            proxy_tag: ["tag:k8s-operator"],
        },
        "autoApprovers": {
            "routes": {
                homelab_cidr: [proxy_tag],
            },
        },
        "grants": [
            {
                "src": ["autogroup:member"],
                "dst": [homelab_cidr],
                "ip": ["*:*"],
            },
        ],
    }

    json.dump(policy, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
