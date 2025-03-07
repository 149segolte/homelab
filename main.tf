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
      version = "2.3.5"
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

locals {
  vault = {
    address       = "https://localhost:8200"
    kv_store_path = "homelab/terraform"
  }
  ssh = {
    public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFJDftX2Fu1EzN9S1hO8LMjBG3qepW+kH7TgD33Dx/d2 one49segolte@yigirus.local"
    private_key = length(var.ssh_private_key_file) > 0 ? file(var.ssh_private_key_file) : null
  }
  os_releases = {
    coreos = {
      url    = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${jsondecode(data.http.coreos_stable_builds.response_body).builds[0].id}/aarch64/${jsondecode(data.http.coreos_stable_aarch64_build.response_body).images.metal.path}"
      sha256 = jsondecode(data.http.coreos_stable_aarch64_build.response_body).images.metal.sha256
    }
    alpine = {
      url = join("", [
        "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/",
        tostring(reverse(
          [for y in
            [for x in
              split("\n", data.http.alpine_stable_builds.response_body) : regex("^<a href=\\\"(.*)\">", x)[0]
              if startswith(x, "<a href=")
            ] : y
            if length(y) > 0 && strcontains(y, "generic") && strcontains(y, "x86_64") && strcontains(y, "bios") && strcontains(y, "cloudinit") && !strcontains(y, "metal") && strcontains(y, ".qcow2") && !strcontains(y, "asc") && !strcontains(y, "sha512")
          ]
        )[0])
      ])
      sha512 = trimspace(data.http.alpine_stable_build_checksum.response_body)
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
      name    = "data_provider"
      restore = false
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
  remote_ignition = {
    hostname = "hetzner-remote-node"
    user = {
      name          = "one49segolte"
      password_hash = "$y$j9T$u9UeIl5kfbBegG44PRQW6/$HAba.BFa9Ky4fTTyfEFQWcEfMXKpbldtBEGirPBvue2"
      groups        = ["wheel", "sudo", "docker"]
    }
  }
}

data "http" "coreos_stable_builds" {
  url = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/builds.json"
  request_headers = {
    Accept = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not get the CoreOS stable builds.json"
    }
  }
}

data "http" "coreos_stable_aarch64_build" {
  url = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${jsondecode(data.http.coreos_stable_builds.response_body).builds[0].id}/aarch64/meta.json"
  request_headers = {
    Accept = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not get the CoreOS stable aarch64 meta.json"
    }
  }
}

data "http" "alpine_stable_builds" {
  url = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/"
  request_headers = {
    Accept = "text/html"
  }

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not get the Alpine Linux stable builds"
    }
  }
}

data "http" "alpine_stable_build_checksum" {
  url = join("", [
    "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/cloud/",
    tostring(reverse(
      [for y in
        [for x in
          split("\n", data.http.alpine_stable_builds.response_body) : regex("^<a href=\\\"(.*)\">", x)[0]
          if startswith(x, "<a href=")
        ] : y
        if length(y) > 0 && strcontains(y, "generic") && strcontains(y, "x86_64") && strcontains(y, "bios") && strcontains(y, "cloudinit") && !strcontains(y, "metal") && strcontains(y, ".qcow2") && !strcontains(y, "asc") && strcontains(y, "sha512")
      ]
    )[0])
  ])

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not get the Alpine Linux stable build checksum"
    }
  }
}
