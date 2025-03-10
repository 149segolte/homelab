provider "vault" {
  # Only use hardcoded values if vault is running locally, otherwise use environment variables like VAULT_ADDR, VAULT_TOKEN, etc.
  address      = local.vault.address
  ca_cert_file = var.vault_cert

  auth_login_userpass {
    username = var.vault_username
    password = var.vault_password
  }
}

data "vault_generic_secret" "healthcheck" {
  path = "sys/health"
}

# output "vault_healthcheck" {
#   value = nonsensitive(data.vault_generic_secret.healthcheck.data)
# }

data "vault_generic_secret" "kv_store" {
  depends_on = [data.vault_generic_secret.healthcheck]
  path       = "sys/mounts/${local.vault.kv_store_path}"

  lifecycle {
    postcondition {
      condition     = provider::assert::true(self.data.type == "kv")
      error_message = "secret engine ${local.vault.kv_store_path} is not a kv store"
    }
    postcondition {
      condition     = provider::assert::valid_json(self.data.options)
      error_message = "kv store ${local.vault.kv_store_path} options are not valid JSON"
    }
    postcondition {
      condition     = provider::assert::true(jsondecode(self.data.options).version == "2")
      error_message = "kv store ${local.vault.kv_store_path} is not version 2"
    }
  }
}

# output "kv_store" {
#   value = nonsensitive(data.vault_generic_secret.kv_store.data)
# }

data "vault_kv_secret_v2" "secret_proxmox" {
  depends_on = [data.vault_generic_secret.kv_store]
  mount      = local.vault.kv_store_path
  name       = "proxmox"

  lifecycle {
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
#   value = nonsensitive(data.vault_kv_secret_v2.secret_proxmox.data)
# }

data "vault_kv_secret_v2" "secret_hetzner" {
  depends_on = [data.vault_generic_secret.kv_store]
  mount      = local.vault.kv_store_path
  name       = "hetzner"

  lifecycle {
    postcondition {
      condition     = provider::assert::key("token", self.data)
      error_message = "kv store does not contain hetzner token"
    }
  }
}

# output "hetzner_token" {
#   value = nonsensitive(data.vault_kv_secret_v2.secret_hetzner.data)
# }

data "vault_kv_secret_v2" "secret_ssh" {
  depends_on = [data.vault_generic_secret.kv_store]
  mount      = local.vault.kv_store_path
  name       = "ssh"

  lifecycle {
    postcondition {
      condition     = provider::assert::key("public_key", self.data)
      error_message = "kv store does not contain ssh public key"
    }
    postcondition {
      condition     = provider::assert::key("private_key", self.data)
      error_message = "kv store does not contain ssh private key"
    }
  }
}

data "vault_kv_secret_v2" "secret_tailscale" {
  depends_on = [data.vault_generic_secret.kv_store]
  mount      = local.vault.kv_store_path
  name       = "tailscale"

  lifecycle {
    postcondition {
      condition     = provider::assert::key("hetzner_client_secret", self.data)
      error_message = "kv store does not contain tailscale hetzner auth key"
    }
  }
}
