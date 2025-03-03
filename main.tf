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
    assert = {
      source  = "hashicorp/assert"
      version = "0.15.0"
    }
  }
}

variable "data_terraform" {
  description = "Path to a dir which contains terraform related files"
  type        = string
  default     = "/Users/one49segolte/Documents"
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

variable "kv_store_path" {
  description = "The path to the kv store"
  type        = string
  default     = "homelab/terraform"
}

provider "vault" {
  # Only use hardcoded values if vault is running locally, otherwise use environment variables like VAULT_ADDR, VAULT_TOKEN, etc.
  address      = "https://127.0.0.1:8200"
  ca_cert_file = "${var.data_terraform}/hc_vault/vault-cert.pem"
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
  path = "sys/mounts/${var.kv_store_path}"
  lifecycle {
    postcondition {
      condition     = provider::assert::true(self.data.type == "kv")
      error_message = "secret engine ${var.kv_store_path} is not a kv store"
    }
    postcondition {
      condition     = provider::assert::valid_json(self.data.options)
      error_message = "kv store ${var.kv_store_path} options are not valid JSON"
    }
    postcondition {
      condition     = provider::assert::true(jsondecode(self.data.options).version == "2")
      error_message = "kv store ${var.kv_store_path} is not version 2"
    }
  }
}

# output "kv_store" {
#   value = nonsensitive(data.vault_generic_secret.kv_store.data)
# }
