<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.2-rc04 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 3.0.2-rc04 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_pool.k8s](https://registry.terraform.io/providers/telmate/proxmox/3.0.2-rc04/docs/resources/pool) | resource |
| [proxmox_vm_qemu.k8s-master](https://registry.terraform.io/providers/telmate/proxmox/3.0.2-rc04/docs/resources/vm_qemu) | resource |
| [proxmox_vm_qemu.k8s-node](https://registry.terraform.io/providers/telmate/proxmox/3.0.2-rc04/docs/resources/vm_qemu) | resource |
| [proxmox_vm_qemu.nginx-lb](https://registry.terraform.io/providers/telmate/proxmox/3.0.2-rc04/docs/resources/vm_qemu) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_boot_order"></a> [boot\_order](#input\_boot\_order) | Boot device order | `string` | `"order=scsi0"` | no |
| <a name="input_bootdisk"></a> [bootdisk](#input\_bootdisk) | Boot disk device | `string` | `"scsi0"` | no |
| <a name="input_cloudinit_storage"></a> [cloudinit\_storage](#input\_cloudinit\_storage) | Storage for cloud-init drive | `string` | `"local-lvm"` | no |
| <a name="input_disk0_cache"></a> [disk0\_cache](#input\_disk0\_cache) | Cache mode for primary disk | `string` | `"writeback"` | no |
| <a name="input_disk0_replicate"></a> [disk0\_replicate](#input\_disk0\_replicate) | Enable replication for primary disk | `bool` | `true` | no |
| <a name="input_disk0_size_gb"></a> [disk0\_size\_gb](#input\_disk0\_size\_gb) | Size of primary disk in GB | `number` | `32` | no |
| <a name="input_disk0_storage"></a> [disk0\_storage](#input\_disk0\_storage) | Storage for primary disk | `string` | `"local-lvm"` | no |
| <a name="input_enable_agent"></a> [enable\_agent](#input\_enable\_agent) | Enable QEMU agent | `bool` | `true` | no |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Network gateway | `string` | `"192.168.1.1"` | no |
| <a name="input_ip_base"></a> [ip\_base](#input\_ip\_base) | Base IP address (first 3 octets) | `string` | `"192.168.1"` | no |
| <a name="input_master_cores"></a> [master\_cores](#input\_master\_cores) | vCPU cores for master | `number` | `2` | no |
| <a name="input_master_count"></a> [master\_count](#input\_master\_count) | Number of master VMs to create | `number` | `1` | no |
| <a name="input_master_ip_host"></a> [master\_ip\_host](#input\_master\_ip\_host) | Last octet for master IP | `number` | `230` | no |
| <a name="input_master_memory"></a> [master\_memory](#input\_master\_memory) | Memory (MB) for master | `number` | `2048` | no |
| <a name="input_master_name"></a> [master\_name](#input\_master\_name) | Master VM name | `string` | `"k8s-master"` | no |
| <a name="input_master_sockets"></a> [master\_sockets](#input\_master\_sockets) | CPU sockets for master | `number` | `1` | no |
| <a name="input_master_tags"></a> [master\_tags](#input\_master\_tags) | Tags for master VM (comma-separated) | `string` | `"k3s,master,terraform"` | no |
| <a name="input_master_vmid"></a> [master\_vmid](#input\_master\_vmid) | VMID for master | `number` | `230` | no |
| <a name="input_net_bridge"></a> [net\_bridge](#input\_net\_bridge) | Network bridge | `string` | `"vmbr0"` | no |
| <a name="input_net_model"></a> [net\_model](#input\_net\_model) | Network interface model | `string` | `"virtio"` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | Network CIDR suffix | `number` | `24` | no |
| <a name="input_nginx_lb_cores"></a> [nginx\_lb\_cores](#input\_nginx\_lb\_cores) | vCPU cores for Nginx load balancer | `number` | `1` | no |
| <a name="input_nginx_lb_ip_host"></a> [nginx\_lb\_ip\_host](#input\_nginx\_lb\_ip\_host) | Last octet for Nginx load balancer IP | `number` | `201` | no |
| <a name="input_nginx_lb_memory"></a> [nginx\_lb\_memory](#input\_nginx\_lb\_memory) | Memory (MB) for Nginx load balancer | `number` | `1024` | no |
| <a name="input_nginx_lb_name"></a> [nginx\_lb\_name](#input\_nginx\_lb\_name) | Name for the Nginx load balancer VM | `string` | `"k8s-nginx-lb"` | no |
| <a name="input_nginx_lb_sockets"></a> [nginx\_lb\_sockets](#input\_nginx\_lb\_sockets) | CPU sockets for Nginx load balancer | `number` | `1` | no |
| <a name="input_nginx_lb_tags"></a> [nginx\_lb\_tags](#input\_nginx\_lb\_tags) | Tags for Nginx load balancer VM (comma-separated) | `string` | `"k8s,loadbalancer,nginx,terraform"` | no |
| <a name="input_nginx_lb_vmid"></a> [nginx\_lb\_vmid](#input\_nginx\_lb\_vmid) | VMID for Nginx load balancer | `number` | `201` | no |
| <a name="input_node_cores"></a> [node\_cores](#input\_node\_cores) | vCPU cores for nodes | `number` | `2` | no |
| <a name="input_node_ip_start"></a> [node\_ip\_start](#input\_node\_ip\_start) | Starting last octet for node IPs | `number` | `231` | no |
| <a name="input_node_memory"></a> [node\_memory](#input\_node\_memory) | Memory (MB) for nodes | `number` | `2048` | no |
| <a name="input_node_name_prefix"></a> [node\_name\_prefix](#input\_node\_name\_prefix) | Prefix for node names | `string` | `"k8s-node"` | no |
| <a name="input_node_sockets"></a> [node\_sockets](#input\_node\_sockets) | CPU sockets for nodes | `number` | `1` | no |
| <a name="input_node_tags"></a> [node\_tags](#input\_node\_tags) | Tags for worker node VMs (comma-separated) | `string` | `"k3s,worker,terraform"` | no |
| <a name="input_node_vmid_start"></a> [node\_vmid\_start](#input\_node\_vmid\_start) | Starting VMID for nodes | `number` | `231` | no |
| <a name="input_nodes_count"></a> [nodes\_count](#input\_nodes\_count) | Number of worker nodes to create | `number` | `3` | no |
| <a name="input_os_type"></a> [os\_type](#input\_os\_type) | OS type for cloud-init | `string` | `"cloud-init"` | no |
| <a name="input_pm_api_token_id"></a> [pm\_api\_token\_id](#input\_pm\_api\_token\_id) | Proxmox API token ID (alternative to user/password) | `string` | `""` | no |
| <a name="input_pm_api_token_secret"></a> [pm\_api\_token\_secret](#input\_pm\_api\_token\_secret) | Proxmox API token secret (alternative to user/password) | `string` | `""` | no |
| <a name="input_pm_api_url"></a> [pm\_api\_url](#input\_pm\_api\_url) | Proxmox API URL | `string` | n/a | yes |
| <a name="input_private_key_path"></a> [private\_key\_path](#input\_private\_key\_path) | Path to private key for remote-exec and Ansible | `string` | n/a | yes |
| <a name="input_scsihw"></a> [scsihw](#input\_scsihw) | SCSI hardware type | `string` | `"virtio-scsi-pci"` | no |
| <a name="input_serial_id"></a> [serial\_id](#input\_serial\_id) | Serial device ID | `number` | `0` | no |
| <a name="input_serial_type"></a> [serial\_type](#input\_serial\_type) | Serial device type | `string` | `"socket"` | no |
| <a name="input_ssh_password"></a> [ssh\_password](#input\_ssh\_password) | SSH password for cloud-init | `string` | n/a | yes |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | SSH public key for VM access | `string` | n/a | yes |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | SSH username for cloud-init | `string` | `"user"` | no |
| <a name="input_target_node"></a> [target\_node](#input\_target\_node) | Proxmox node to create VMs on | `string` | n/a | yes |
| <a name="input_template_name"></a> [template\_name](#input\_template\_name) | Name of the Proxmox template to clone | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_info"></a> [cluster\_info](#output\_cluster\_info) | K3s HA cluster information |
| <a name="output_kubeconfig_command"></a> [kubeconfig\_command](#output\_kubeconfig\_command) | Command to copy kubeconfig from first master |
| <a name="output_master_ssh_connections"></a> [master\_ssh\_connections](#output\_master\_ssh\_connections) | SSH connection commands for all masters |
| <a name="output_nginx_lb_ssh_connection"></a> [nginx\_lb\_ssh\_connection](#output\_nginx\_lb\_ssh\_connection) | SSH connection command for Nginx load balancer |
| <a name="output_proxmox_master_default_ip_addresses"></a> [proxmox\_master\_default\_ip\_addresses](#output\_proxmox\_master\_default\_ip\_addresses) | Default IP addresses of all master VMs |
| <a name="output_proxmox_master_static_ip_addresses"></a> [proxmox\_master\_static\_ip\_addresses](#output\_proxmox\_master\_static\_ip\_addresses) | Static IP addresses of all master VMs |
| <a name="output_proxmox_nodes_default_ip_addresses"></a> [proxmox\_nodes\_default\_ip\_addresses](#output\_proxmox\_nodes\_default\_ip\_addresses) | Default IP addresses of the worker node VMs |
| <a name="output_worker_ssh_connections"></a> [worker\_ssh\_connections](#output\_worker\_ssh\_connections) | SSH connection commands for workers |
<!-- END_TF_DOCS -->