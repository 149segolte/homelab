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

data "vault_kv_secret_v2" "tokens" {
  depends_on = [data.vault_generic_secret.kv_store]
  mount      = local.vault.kv_store_path
  name       = "tokens"

  lifecycle {
    postcondition {
      condition     = provider::assert::key("proxmox_api", self.data)
      error_message = "kv store does not contain proxmox api token"
    }
    postcondition {
      condition     = provider::assert::key("hetzner_api", self.data)
      error_message = "kv store does not contain hetzner api token"
    }
    postcondition {
      condition     = provider::assert::key("cloudflare_api", self.data)
      error_message = "kv store does not contain cloudflare api token"
    }
    postcondition {
      condition     = provider::assert::key("tailscale_client_secret", self.data)
      error_message = "kv store does not contain tailscale client secret"
    }
    postcondition {
      condition     = provider::assert::key("quay_io_packer", self.data)
      error_message = "kv store does not contain quay.io packer token"
    }
  }
}

data "vault_kv_secret_v2" "variables" {
  depends_on = [data.vault_generic_secret.kv_store]
  mount      = local.vault.kv_store_path
  name       = "variables"

  lifecycle {
    postcondition {
      condition     = provider::assert::key("cloudflare_email", self.data)
      error_message = "kv store does not contain cloudflare email"
    }
    postcondition {
      condition     = provider::assert::key("ssh_public_key", self.data)
      error_message = "kv store does not contain ssh public key"
    }
    postcondition {
      condition     = provider::assert::key("quay_io_packer", self.data)
      error_message = "kv store does not contain quay.io packer username"
    }
  }
}
