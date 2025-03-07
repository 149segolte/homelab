provider "proxmox" {
  endpoint = local.proxmox.node.endpoint
  username = join("@", [local.proxmox.credentials.username, "pam"])
  password = local.proxmox.credentials.password

  # because self-signed TLS certificate is in use
  insecure = true

  ssh {
    username = local.proxmox.credentials.username
    password = local.proxmox.credentials.password
    agent    = false
  }

  random_vm_ids = false
}

data "proxmox_virtual_environment_nodes" "available_nodes" {
  lifecycle {
    postcondition {
      condition     = provider::assert::true(length(self.names) > 0)
      error_message = "No nodes available in the proxmox environment"
    }
  }
}

# output "proxmox_nodes" {
#   value = data.proxmox_virtual_environment_nodes.available_nodes
# }

data "proxmox_virtual_environment_node" "node" {
  depends_on = [data.proxmox_virtual_environment_nodes.available_nodes]
  node_name  = local.proxmox.node.name
}

# output "proxmox_node" {
#   value = nonsensitive(data.proxmox_virtual_environment_node.node)
# }
