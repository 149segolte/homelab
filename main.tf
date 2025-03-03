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

locals {
  vault_cert    = "/Users/one49segolte/Documents/hc_vault/vault-cert.pem"
  kv_store_path = "homelab/terraform"
}

provider "vault" {
  # Only use hardcoded values if vault is running locally, otherwise use environment variables like VAULT_ADDR, VAULT_TOKEN, etc.
  address      = "https://127.0.0.1:8200"
  ca_cert_file = local.vault_cert
  auth_login_userpass {
    username = var.vault_username
    password = var.vault_password
  }
}

data "vault_generic_secret" "healthcheck" {
  path = "sys/health"
  lifecycle {
    postcondition {
      condition     = provider::assert::true(self.data.initialized)
      error_message = "The vault instance is not initialized"
    }
    postcondition {
      condition     = provider::assert::false(self.data.sealed)
      error_message = "The vault instance is sealed"
    }
  }
}

# output "vault_healthcheck" {
#   value = nonsensitive(data.vault_generic_secret.healthcheck.data)
# }

data "vault_generic_secret" "kv_store" {
  path = "sys/mounts/${local.kv_store_path}"
  lifecycle {
    postcondition {
      condition     = provider::assert::true(self.data.type == "kv")
      error_message = "secret engine ${local.kv_store_path} is not a kv store"
    }
    postcondition {
      condition     = provider::assert::valid_json(self.data.options)
      error_message = "kv store ${local.kv_store_path} options are not valid JSON"
    }
    postcondition {
      condition     = provider::assert::true(jsondecode(self.data.options).version == "2")
      error_message = "kv store ${local.kv_store_path} is not version 2"
    }
  }
}

# output "kv_store" {
#   value = nonsensitive(data.vault_generic_secret.kv_store.data)
# }

data "vault_kv_secret_v2" "data_proxmox" {
  mount = local.kv_store_path
  name  = "proxmox"
  lifecycle {
    postcondition {
      condition     = provider::assert::key("endpoint", self.data)
      error_message = "kv store does not contain proxmox endpoint"
    }
    postcondition {
      condition     = provider::assert::key("username", self.data)
      error_message = "kv store does not contain proxmox username"
    }
    postcondition {
      condition     = provider::assert::key("password", self.data)
      error_message = "kv store does not contain proxmox password"
    }
  }
}

# output "proxmox_credentials" {
#   value = nonsensitive(data.vault_kv_secret_v2.data_proxmox.data)
# }

provider "proxmox" {
  endpoint = data.vault_kv_secret_v2.data_proxmox.data["endpoint"]
  username = data.vault_kv_secret_v2.data_proxmox.data["username"]
  password = data.vault_kv_secret_v2.data_proxmox.data["password"]

  # because self-signed TLS certificate is in use
  insecure = true
}

data "proxmox_virtual_environment_nodes" "available_nodes" {}

# output "proxmox_nodes" {
#   value = data.proxmox_virtual_environment_nodes.available_nodes
# }
