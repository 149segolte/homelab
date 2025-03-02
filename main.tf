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
  }
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
}

output "health" {
  value = nonsensitive(data.vault_generic_secret.healthcheck.data)
}
