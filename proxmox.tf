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

data "proxmox_virtual_environment_node" "node" {
  depends_on = [data.proxmox_virtual_environment_nodes.available_nodes]
  node_name  = local.proxmox.node.name
}

data "proxmox_virtual_environment_datastores" "datastores" {
  node_name = data.proxmox_virtual_environment_node.node.node_name

  lifecycle {
    postcondition {
      condition     = contains(flatten(self.content_types), "iso")
      error_message = "No ISO datastores available in the proxmox environment"
    }
    postcondition {
      condition     = contains(flatten(self.content_types), "snippets")
      error_message = "No snippets datastores available in the proxmox environment"
    }
    postcondition {
      condition     = contains(flatten(self.content_types), "images")
      error_message = "No images datastores available in the proxmox environment"
    }
  }
}

locals {
  iso_datastore_id      = element(data.proxmox_virtual_environment_datastores.datastores.datastore_ids, tonumber(transpose(zipmap(range(length(data.proxmox_virtual_environment_datastores.datastores.content_types)), data.proxmox_virtual_environment_datastores.datastores.content_types))["iso"][0]))
  snippets_datastore_id = element(data.proxmox_virtual_environment_datastores.datastores.datastore_ids, tonumber(transpose(zipmap(range(length(data.proxmox_virtual_environment_datastores.datastores.content_types)), data.proxmox_virtual_environment_datastores.datastores.content_types))["snippets"][0]))
  images_datastore_id   = element(data.proxmox_virtual_environment_datastores.datastores.datastore_ids, tonumber(transpose(zipmap(range(length(data.proxmox_virtual_environment_datastores.datastores.content_types)), data.proxmox_virtual_environment_datastores.datastores.content_types))["images"][0]))
}

resource "proxmox_virtual_environment_download_file" "alpine_cloudinit_qcow2" {
  node_name    = data.proxmox_virtual_environment_node.node.node_name
  datastore_id = local.iso_datastore_id
  content_type = "iso"
  file_name    = join(".", [reverse(split("/", local.os_releases.custom_alpine.url))[0], "img"])
  url          = local.os_releases.custom_alpine.url
}

resource "proxmox_virtual_environment_file" "data_provider_config" {
  content_type = "snippets"
  datastore_id = local.snippets_datastore_id
  node_name    = data.proxmox_virtual_environment_node.node.node_name

  source_raw {
    data = templatefile("${path.module}/proxmox/data_provider/cloud-config.yml.tftpl", {
      hostname       = local.proxmox.data_provider.name
      username       = local.user.name
      groups         = join(",", local.user.groups)
      ssh_public_key = local.user.ssh.public_key
      nfs_shares     = [local.hetzner.node.name]
    })

    file_name = "data_provider.cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "data_provider" {
  count       = local.proxmox.data_provider.restore ? 0 : 1
  name        = "data-provider"
  description = "Proxmox data provider"
  node_name   = data.proxmox_virtual_environment_node.node.node_name
  machine     = "q35"
  vm_id       = 4201

  agent {
    enabled = true
  }

  on_boot = true
  startup {
    order      = "1"
    up_delay   = "30"
    down_delay = "30"
  }

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
    floating  = 2048
  }

  network_device {
    bridge = local.proxmox.node.vm_bridge
  }

  operating_system {
    type = "l26"
  }

  disk {
    datastore_id = local.images_datastore_id
    file_id      = proxmox_virtual_environment_download_file.alpine_cloudinit_qcow2.id
    interface    = "scsi0"
    size         = 1
    backup       = true
  }

  disk {
    datastore_id = local.images_datastore_id
    interface    = "scsi1"
    size         = 16
    file_format  = "qcow2"
    backup       = true
  }

  initialization {
    datastore_id      = local.images_datastore_id
    user_data_file_id = proxmox_virtual_environment_file.data_provider_config.id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  tags = ["homelab"]
}
