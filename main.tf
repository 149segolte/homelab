terraform {
  backend "local" {
    # Backup using any utilities like rsync, scp, rclone, syncthing, etc.
    path = "/Users/one49segolte/Documents/terraform_states/homelab.tfstate"
  }
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.6.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.73.0"
    }
    assert = {
      source  = "hashicorp/assert"
      version = "0.15.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.50.0"
    }
  }
}

variable "vault_username" {
  description = "The username for the local vault user"
  type        = string
}

variable "vault_password" {
  description = "The password for the local vault user"
  type        = string
  sensitive   = true
}

variable "vault_cert" {
  description = "The path to the vault certificate"
  type        = string
  sensitive   = true
}

variable "ssh_private_key_file" {
  description = "The path to the private key for SSH, leave empty if using agent"
  type        = string
  sensitive   = true
}

variable "internal_network" {
  description = "Whether the proxmox environment is on an internal network"
  type        = bool
  default     = false
}

locals {
  vault = {
    address       = "https://localhost:8200"
    kv_store_path = "homelab/terraform"
  }
  ssh = {
    public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFJDftX2Fu1EzN9S1hO8LMjBG3qepW+kH7TgD33Dx/d2 one49segolte@yigirus.local"
    private_key = length(var.ssh_private_key_file) > 0 ? file(var.ssh_private_key_file) : null
  }
  proxmox = {
    credentials = {
      username = data.vault_kv_secret_v2.secret_proxmox.data["username"]
      password = data.vault_kv_secret_v2.secret_proxmox.data["password"]
    }
    node = {
      name              = "novasking"
      endpoint_external = "https://192.168.0.51:8006"
      endpoint_internal = "https://novasking.proxmox.arpa:8006"
    }
  }
  hetzner = {
    client = {
      token         = data.vault_kv_secret_v2.secret_hetzner.data["token"]
      poll_interval = "1000ms"
    }
    node = {
      name     = "hetzner-remote-node"
      type     = "cax11"
      location = "hel1"
    }
  }
}
