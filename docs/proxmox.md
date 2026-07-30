# Proxmox configuration

API access, cloud-init (Debian) templates, and the Talos disk image used when
deploying with `--os=talos`. Secrets live in `secrets.env`. VM sizing and node
placement are in:

- `terrafrom/linux/terraform.tfvars` — K3s
- `terrafrom/talos-linux/terraform.tfvars` — Talos (CP/workers + LB template IDs)

---

## Proxmox API (secrets)

```bash
PROXMOX_ENDPOINT="https://172.16.33.2:8006/"
PROXMOX_API_TOKEN="root@pam!terraform=CHANGE_ME"
PROXMOX_INSECURE=true
PROXMOX_SSH_USERNAME=root
```

| Variable | Description |
|----------|-------------|
| `PROXMOX_ENDPOINT` | Proxmox API URL (`:8006`). |
| `PROXMOX_API_TOKEN` | `USER@REALM!TOKENID=UUID`. |
| `PROXMOX_INSECURE` | `true` for the default self-signed cert. |
| `PROXMOX_SSH_USERNAME` | SSH user for provider ops that need a shell (usually `root`). |

### API token

**UI:** Datacenter → Permissions → API Tokens → Add  
User `root@pam`, Token ID e.g. `terraform`. Uncheck Privilege Separation (or grant
ACLs). Copy the UUID once.

```bash
pveum user token add root@pam terraform --privsep 0
# value: root@pam!terraform=<uuid>
```

---

## Two templates (important for Talos)

| Role | Vars / tfvars | OS |
|------|----------------|-----|
| API LB (HAProxy) | `TEMPLATE_*` in `secrets.env`, and `lb_template_*` in `terrafrom/talos-linux/terraform.tfvars` | **Debian** cloud-init |
| Control plane + workers | `template_*` in `terrafrom/talos-linux/terraform.tfvars` (documented as `TALOS_TEMPLATE_*` in `secrets.env.example`) | **Talos** disk image |

`--os=linux` clones **only** the Debian/cloud-init template for LB, leaders, and
workers.

`--os=talos` clones **Debian for the LB** and **Talos for leaders/workers**.

Node names are `node1`…`node5`. `*_NODE` / `*_template_node` must be the Proxmox
node where that template VM actually exists.

---

## Debian cloud-init template (LB + K3s)

```bash
TEMPLATE_NAME=Debian13-cloud
TEMPLATE_VM_ID=9003
TEMPLATE_NODE=node1
ENV_ID=k8s-homelab
VM_TAGS="k8s k8s-homelab terraform"
```

| Variable | Description |
|----------|-------------|
| `TEMPLATE_NAME` | Template display name |
| `TEMPLATE_VM_ID` | Template VMID |
| `TEMPLATE_NODE` | Node hosting the template |
| `ENV_ID` | Pool name, VM names, inventory path |
| `VM_TAGS` | Proxmox tags (role tags added by Terraform) |

### Build (on a Proxmox node)

```bash
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2

qm create 9003 --name Debian13-cloud --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9003 debian-13-genericcloud-amd64.qcow2 local-lvm   # or ceph-prod
qm set 9003 --scsihw virtio-scsi-single --scsi0 local-lvm:vm-9003-disk-0
qm set 9003 --ide2 local-lvm:cloudinit
qm set 9003 --boot order=scsi0 --serial0 socket --vga serial0
qm set 9003 --agent enabled=1
qm template 9003
```

Enable qemu-guest-agent so cloud-init VMs report IPs cleanly.

For Talos stack LB settings, mirror the same VMID/node in
`terrafrom/talos-linux/terraform.tfvars`:

```hcl
lb_template_name  = "Debian13-cloud"
lb_template_vm_id = 9003
lb_template_node  = "node1"
```

---

## Talos template (CP + workers)

Used only with `./deploy-infra.sh --os=talos`.

Documented in `secrets.env.example` (keep in sync with tfvars):

```bash
TALOS_TEMPLATE_NAME=talos-os
TALOS_TEMPLATE_VM_ID=9006
TALOS_TEMPLATE_NODE=node1
# optional pin if Image Factory lookup fails during bootstrap:
# TALOS_INSTALLER_SCHEMATIC=<schematic-id>
```

Actual clone source for Terraform is `terrafrom/talos-linux/terraform.tfvars`:

```hcl
template_name  = "talos-os"
template_vm_id = 9006
template_node  = "node1"
```

### 1. Image Factory

Open [factory.talos.dev](https://factory.talos.dev/) and build a **metal** (or
**nocloud**) amd64 image for your Talos version.

**This lab’s Proxmox template (`talos-os`) includes:**

- `siderolabs/qemu-guest-agent` — required for Proxmox guest agent / IP reporting
- `siderolabs/intel-ucode` — CPU microcode

Download the **qcow2** (or decompress `.raw.zst` / `.raw.xz`) for that schematic.

**Longhorn (separate from the clone template):** at bootstrap,
`bootstrap-talos.sh` resolves an installer schematic with
`iscsi-tools` + `util-linux-tools` (+ guest agent) and may upgrade nodes to
`factory.talos.dev/installer/<schematic>:<version>`. Pin with
`TALOS_INSTALLER_SCHEMATIC` in `secrets.env` if needed. You can also bake those
into the base image if you prefer not to upgrade at first boot.
### 2. Import as Proxmox template

Adjust VMID, storage (`local-lvm` / `ceph-prod`), and bridge to match your lab:

```bash
# example: factory metal qcow2 already downloaded
qm create 9006 --name talos-os --memory 4096 --cores 2 \
  --net0 virtio,bridge=vmbr0 --ostype l26 \
  --scsihw virtio-scsi-single --cpu host

qm importdisk 9006 metal-amd64.qcow2 ceph-prod
qm set 9006 --scsi0 ceph-prod:vm-9006-disk-0,discard=on
qm set 9006 --boot order=scsi0
qm set 9006 --serial0 socket --vga serial0
# guest agent — image must include siderolabs/qemu-guest-agent
qm set 9006 --agent enabled=1

qm template 9006
```

Then set `template_vm_id` / `template_node` (and `TALOS_TEMPLATE_*`) to match.

Notes:

- Talos nodes have **no SSH**. After clone, bootstrap is via `talosctl`
  (`scripts/bootstrap-talos.sh`).
- qemu-guest-agent must be in the **image extensions**; enabling the Proxmox
  agent flag alone is not enough.
- Workers get an extra data disk from Terraform (`worker_data_disk_*`) for
  Longhorn; that is not part of the template disk.

### 3. Deploy

```bash
./deploy-infra.sh -y --os=talos
```

Flow: Terraform clones LB (Debian) + Talos VMs → Ansible HAProxy on LB →
`bootstrap-talos.sh` → Helm.

---

## Related

- Network / SSH / counts: `secrets.env`, [platform.md](platform.md)
- Placement / HA / PBS: `terrafrom/*/terraform.tfvars`
- Getting started: [getting-started.md](getting-started.md)
- Longhorn on Talos: [toggles/longhorn.md](toggles/longhorn.md)
