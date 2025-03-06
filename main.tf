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
}
