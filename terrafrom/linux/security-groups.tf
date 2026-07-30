resource "proxmox_virtual_environment_firewall_rules" "homelab" {
  count = var.manage_firewall ? 1 : 0

  node_name = var.target_node

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "${var.environment} SSH"
    proto   = "tcp"
    dport   = "22"
    source  = join(",", var.firewall_allowed_cidrs)
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "${var.environment} HTTPS"
    proto   = "tcp"
    dport   = "443"
    source  = join(",", var.firewall_allowed_cidrs)
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    comment = "${var.environment} HTTP"
    proto   = "tcp"
    dport   = "80"
    source  = join(",", var.firewall_allowed_cidrs)
    enabled = true
  }
}
