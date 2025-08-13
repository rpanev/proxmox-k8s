resource "proxmox_pool" "k8s" {
  poolid  = "k8s"
  comment = "Pool for k8s cluster"
}
