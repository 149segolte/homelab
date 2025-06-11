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
    ignition = {
      source  = "community-terraform-providers/ignition"
      version = "2.4.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
    packer = {
      source  = "toowoxx/packer"
      version = "0.16.1"
    }
  }
}

provider "packer" {}
data "packer_version" "ver" {}

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

locals {
  vault = {
    address       = "https://localhost:8200"
    kv_store_path = "homelab/terraform"
  }
  domain = {
    base   = "149segolte.dev"
    remote = "pub.149segolte.dev"
    local  = "pri.149segolte.dev"
  }
  user = {
    name          = "one49segolte"
    password      = random_password.password.result
    password_hash = random_password.password.bcrypt_hash
    groups        = ["wheel", "sudo"]
    ssh = {
      public_key  = data.vault_kv_secret_v2.secret_ssh.data["public_key"]
      private_key = data.vault_kv_secret_v2.secret_ssh.data["private_key"]
    }
  }
  os_releases = {
    coreos = {
      url      = jsondecode(data.http.coreos_stable_builds.response_body).architectures.aarch64.artifacts.hetzner.formats["raw.xz"].disk.location
      checksum = jsondecode(data.http.coreos_stable_builds.response_body).architectures.aarch64.artifacts.hetzner.formats["raw.xz"].disk.sha256
    }
    custom_alpine = {
      url = join("", [
        "https://github.com/149segolte/alpine-make-vm-image/releases/download/",
        distinct([
          for x in split("\n", data.http.custom_alpine_build.response_body) : regexall("^.*(action/\\d*T\\d*Z)", x)[0][0]
          if strcontains(x, "action/")
        ])[0],
        "/custom_alpine-x86_64-bios-cloudinit.qcow2"
      ])
      checksum = "none"
    }
  }
  proxmox = {
    credentials = {
      username = data.vault_kv_secret_v2.secret_proxmox.data["username"]
      password = data.vault_kv_secret_v2.secret_proxmox.data["password"]
    }
    node = {
      name      = "novasking"
      vm_bridge = "vmbr2"
      endpoint  = "https://novasking.proxmox.arpa:8006"
      # endpoint  = "https://192.168.0.51:8006"
    }
    data_provider = {
      name    = "dataprovider"
      restore = false
    }
  }
  hetzner = {
    client = {
      token         = data.vault_kv_secret_v2.secret_hetzner.data["token"]
      poll_interval = "1000ms"
    }
    timezone = "Europe/Berlin"
    node = {
      name         = "hetzner-remote-node"
      type         = "cax11"
      location     = "hel1"
      backup_mount = "/var/mnt/backup"
    }
  }
  tailscale = {
    hetzner_key = data.vault_kv_secret_v2.secret_tailscale.data["hetzner_client_secret"]
  }
  cloudflare = {
    email        = data.vault_kv_secret_v2.secret_cloudflare.data["email"]
    api_token    = data.vault_kv_secret_v2.secret_cloudflare.data["api_token"]
    tunnel_token = data.vault_kv_secret_v2.secret_cloudflare.data["tunnel_token"]
    acme = {
      # url   = "https://acme-v02.api.letsencrypt.org/directory"
      url   = "https://acme-staging-v02.api.letsencrypt.org/directory"
      email = "admin@${local.domain.base}"
    }
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

data "http" "coreos_stable_builds" {
  url = "https://builds.coreos.fedoraproject.org/streams/stable.json"
  request_headers = {
    Accept = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not get the CoreOS stable builds"
    }
  }
}

data "http" "custom_alpine_build" {
  url = "https://github.com/149segolte/alpine-make-vm-image/releases/latest"
  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not get the latest custom Alpine release"
    }
  }
}
