terraform {
  backend "local" {
    # Backup using any utilities like rsync, scp, rclone, syncthing, etc.
    path = "/Users/one49segolte/Documents/terraform_states/homelab.tfstate"
  }
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    assert = {
      source  = "hashicorp/assert"
      version = "~> 0.15.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.50"
    }
    butane = {
      source  = "KeisukeYamashita/butane"
      version = "~> 0.1.3"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73.0"
    }
    packer = {
      source  = "toowoxx/packer"
      version = "~> 0.16.1"
    }
  }
}

variable "vault_username" {
  description = "Username for the vault server user"
  type        = string
  nullable    = false
}

variable "vault_password" {
  description = "Password for the vault server user"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "hetzner_data_restore" {
  description = "Flag for disabling/removing Hetzner resources to allow data restore"
  type        = bool
  nullable    = false
  default     = false
}

locals {
  vault = {
    address       = "http://localhost:8200"
    kv_store_path = "homelab/terraform"
    username      = var.vault_username
    password      = var.vault_password
  }

  domain = {
    base   = "149segolte.dev"
    remote = "pub.149segolte.dev"
    local  = "pri.149segolte.dev"
  }

  user = {
    name    = "one49segolte"
    groups  = ["wheel", "sudo"]
    uid     = 1000
    ssh_key = data.vault_kv_secret_v2.variables.data["ssh_public_key"]
    password = {
      value = random_password.password.result
      hash  = random_password.password.bcrypt_hash
    }
  }

  terraform = {
    ssh_key = {
      private = tls_private_key.terraform_use.private_key_openssh
      public  = tls_private_key.terraform_use.public_key_openssh
    }
  }

  proxmox = {
    token = data.vault_kv_secret_v2.tokens.data["proxmox_api"]
    node = {
      name      = "novasking"
      vm_bridge = "vmbr2"
      endpoint  = "https://novasking.proxmox.arpa:8006"
      # endpoint  = "https://192.168.0.51:8006"
    }
  }

  hetzner = {
    client = {
      token         = data.vault_kv_secret_v2.tokens.data["hetzner_api"]
      poll_interval = "1000ms"
    }
    restore  = var.hetzner_data_restore
    timezone = "Europe/Berlin"
    location = "fsn1"
    node = {
      name = "homelab-remote"
      type = "cax11"
    }
  }

  cloudflare = {
    email     = data.vault_kv_secret_v2.variables.data["cloudflare_email"]
    api_token = data.vault_kv_secret_v2.tokens.data["cloudflare_api"]
    acme = {
      # url   = "https://acme-v02.api.letsencrypt.org/directory"
      url   = "https://acme-staging-v02.api.letsencrypt.org/directory"
      email = "admin@${local.domain.base}"
    }
  }

  quay = {
    base     = "quay.io/149segolte"
    username = data.vault_kv_secret_v2.variables.data["quay_io_packer"]
    password = data.vault_kv_secret_v2.tokens.data["quay_io_packer"]
  }
}

resource "random_password" "password" {
  length      = 16
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

resource "tls_private_key" "terraform_use" {
  algorithm = "ED25519"
}

data "http" "coreos_stable_builds" {
  url = "https://builds.coreos.fedoraproject.org/streams/stable.json"
  request_headers = {
    Accept = "application/json"
  }
}

