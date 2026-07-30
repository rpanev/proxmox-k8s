# K3s customization — план за homelab

> Записано за по-късна имплементация. Контекст: K3s на Alma в Proxmox, 2 CP + HAProxy LB,
> Longhorn, Gateway API (Envoy + MetalLB + Cloudflare TLS), Argo CD, Sealed Secrets, Reloader, Velero.
> Tailscale ingress — опционален (remote VPN).

## Текущо състояние

Вече **не е „curl | sh и готово“**:

- HA: 2 control plane + HAProxy на `.210`
- Pinned `K3S_VERSION` в `secrets.env`
- TLS SAN-и за LB + leader IP-та (`ansible/roles/k3s_leader`)
- Alma 10: nftables kube-proxy mode (`k3s_prereqs`)
- swap off, sysctl, kernel modules
- Longhorn като storage, Gateway API за LAN ingress

Оставащото „дефолтно“ е предимно **bundled K3s компоненти** и липса на явна политика за backup/организация.

---

## Фаза 1 — high ROI (препоръчително първо)

### 1. Disable bundled компоненти (дублират платформата)

| K3s bundled | Ползваме | Действие |
|-------------|----------|----------|
| Traefik | Envoy Gateway | `disable: traefik` |
| ServiceLB (klipper) | MetalLB | `disable: servicelb` |
| local-path | Longhorn (default SC) | `disable: local-storage` |

**Защо:** един ingress, един LB, един storage — без конфликти и излишни pods.

### 2. Явна мрежова схема

В `/etc/rancher/k3s/config.yaml` (Ansible template):

- `cluster-cidr` / `service-cidr` — pinned (дори 10.42.0.0/16 и 10.43.0.0/16), документирани
- `cluster-domain: cluster.local`
- Разширени `tls-san` при нужда: `homelab.panev.cloud`, API hostname

### 3. Etcd snapshots (control plane DR)

Velero backup-ва K8s **ресурси**; **не** замества etcd snapshot за CP disaster recovery.

- `etcd-snapshot-schedule-cron` (напр. `0 */6 * * *`)
- `etcd-snapshot-retention` + dir на persistent path

### 4. Node labels

От inventory / `ENV_ID`:

**Workers (agent):**
- `homelab.panev.cloud/role=worker`
- `homelab.panev.cloud/env=k8s-homelab` (или `{{ env_id }}`)

**Control plane:** taints вече са default — labels по желание.

---

## Фаза 2 — среден приоритет

- **Secrets encryption at rest** (`secrets-encryption`) — нужен key management + процедура при restore
- **API audit log** — `kube-apiserver-arg: audit-log-*`
- **Pod Security Standards** — `baseline` за platform NS, `restricted` за app NS (през GitOps/Argo)
- **ResourceQuota / LimitRange** в `gitops/apps` — предотвратява resource hogging

---

## Не правим (overkill за homelab)

- Cilium вместо flannel
- Отделен etcd cluster
- Пълен CIS hardening
- Service mesh (Istio/Linkerd)

---

## Не пипаме

- **Flannel** — default на K3s, работи с Gateway API
- **metrics-server** — bundled в K3s
- **HA модел** — HAProxy + 2 CP е разумен за homelab

---

## Какво значи „професионално“ тук

1. Един ingress (Gateway), един LB (MetalLB), един storage (Longhorn)
2. Явна конфигурация в Ansible/Git — не K3s defaults
3. Два backup слоя: **Velero** (apps) + **etcd snapshots** (control plane)
4. Политики за apps през Argo/GitOps, не в install script

---

## Имплементация

### Фаза 1 — в Ansible (2026-06-19)

- `ansible/roles/k3s_leader/templates/config.yaml.j2` — disable traefik/servicelb/local-storage, CIDR, etcd snapshots, CP labels
- `ansible/roles/k3s_worker/templates/config.yaml.j2` — worker labels
- `scripts/lib/common.sh` — `k3s_extra_tls_sans` от `GATEWAY_DOMAIN`
- `deploy_envoy_gateway` — `cleanup_k3s_traefik()` + `GatewayClass eg`

**Приложи на жив клъстер** (рестарт на K3s nodes):

```bash
./deploy-infra.sh --infra-only -y          # terraform + inventory + k3s.yml
cd ansible && ansible-playbook playbooks/deploy.yml \
  -i inventories/k8s-homelab/hosts.yml \
  --limit k3s_first_leader:k3s_additional_leaders:k3s_workers
./deploy-infra.sh --helm-only -y           # helm stack след K3s restart
```

Или пълен redeploy: `./destroy-infra.sh -y && ./deploy-infra.sh -y`

### Фаза 2 — pending

---

## Бележки за инфра

- `GATEWAY_LB_IP=192.168.99.211`, `GATEWAY_DOMAIN=homelab.panev.cloud`
- `TAILSCALE_ENABLED=false` — OK; LAN достъп през Gateway
- `ARGOCD_BOOTSTRAP_ENABLED` — може `false` докато няма git repo
