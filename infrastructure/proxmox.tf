provider "proxmox" {
  endpoint      = local.proxmox.node.endpoint
  api_token     = local.proxmox.token
  random_vm_ids = false

  # because self-signed TLS certificate is in use
  insecure = true
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

resource "proxmox_virtual_environment_download_file" "coreos_qcow2" {
  content_type = "iso"
  datastore_id = local.iso_datastore_id
  node_name    = data.proxmox_virtual_environment_node.node.node_name

  file_name = join(".", [reverse(split("/", local.proxmox.images.coreos.url))[0], "img"])
  url       = local.proxmox.images.coreos.url

  checksum                = local.proxmox.images.coreos.checksum
  checksum_algorithm      = "sha256"
  decompression_algorithm = "zst"

  lifecycle {
    ignore_changes = [file_name, url, checksum]
  }
}

resource "proxmox_virtual_environment_file" "data_provider_config" {
  content_type = "snippets"
  datastore_id = local.snippets_datastore_id
  node_name    = data.proxmox_virtual_environment_node.node.node_name

  source_raw {
    file_name = "data_provider.ign"
    data      = data.butane_config.data_provider.ignition
  }
}

resource "proxmox_virtual_environment_vm" "data_provider" {
  name        = "data_provider"
  description = "Proxmox data provider (NFS, SFTP, Vault etc)"
  node_name   = data.proxmox_virtual_environment_node.node.node_name
  machine     = "q35"
  vm_id       = 4201

  agent {
    enabled = true
  }

  on_boot = true
  startup {
    order      = "1"
    up_delay   = "15"
    down_delay = "15"
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
    datastore_id = local.iso_datastore_id
    file_id      = proxmox_virtual_environment_download_file.coreos_qcow2.id
    interface    = "scsi0"
    size         = 12
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
