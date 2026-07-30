# Documentation

Configuration and operations for this homelab. Runtime config lives in
`secrets.env` (from `secrets.env.example`). These pages explain what to set and
how components fit together.

## Start here

| Doc | Description |
|-----|-------------|
| [getting-started.md](getting-started.md) | First deploy checklist |
| [architecture.md](architecture.md) | Pipeline, VMs, IPs, screenshots |
| [toggles/README.md](toggles/README.md) | **Platform toggles** — one page each |
| [../README.md](../README.md) | Project overview + architecture diagram |

## Infrastructure

| Doc | Description |
|-----|-------------|
| [proxmox.md](proxmox.md) | Proxmox API token, templates, pool |
| [platform-os-bg.md](platform-os-bg.md) | `--os=linux\|talos` (Bulgarian) |
| [platform.md](platform.md) | Hostnames, sizing, Grafana password |
| [cloudflare-gateway.md](cloudflare-gateway.md) | Gateway API, MetalLB, DNS-01, Universal SSL |
| [k3s-customization-plan.md](k3s-customization-plan.md) | K3s hardening roadmap |

## Images

Screenshots and diagrams live in [`img/`](img/):

| File | What it shows |
|------|----------------|
| [homelab-architecture.jpg](img/homelab-architecture.jpg) | Overview graphic (README) |
| [homelab-infrastructure-diagram.jpg](img/homelab-infrastructure-diagram.jpg) | Infra flow diagram (`architecture.md`) |
| [longhorn-dashboard.png](img/longhorn-dashboard.png) | Longhorn volumes / storage nodes |
| [grafana-homelab-dashboards.png](img/grafana-homelab-dashboards.png) | Grafana Homelab folder |
| [grafana-k8s-views-global.png](img/grafana-k8s-views-global.png) | Cluster overview |
| [grafana-logging-loki.png](img/grafana-logging-loki.png) | Loki logging |
| [grafana-cert-manager.png](img/grafana-cert-manager.png) | Wildcard cert status |

## Variable groups (not toggles)

Documented in `secrets.env.example` and linked pages:

- **SSH / cloud-init** — `SSH_USER`, `SSH_PASSWORD`, `SSH_PUBLIC_KEY`
- **Network** — `NETWORK_*`, `IP_BASE`, `DNS_*`
- **Cluster size** — `LEADER_COUNT`, `WORKER_COUNT`
- **K3s** — `K3S_VERSION` (`--os=linux`)
- **Talos** — `TALOS_TEMPLATE_*` (`--os=talos`)

Local notes: [`../summary.md`](../summary.md) (gitignored).
