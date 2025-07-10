packer {
  required_plugins {
    hcloud = {
      source  = "github.com/hetznercloud/hcloud"
      version = "~> 1.6"
    }
  }
}

variable "token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Hetzner Cloud location for the image snapshot"
  type        = string
}

variable "architecture" {
  description = "Architecture for the Hetzner Cloud image"
  type        = string

  validation {
    condition     = contains(["x86_64", "aarch64"], var.architecture)
    error_message = "Architecture must be either 'x86_64' or 'aarch64'."
  }
}

data "http" "coreos_stable_builds" {
  url = "https://builds.coreos.fedoraproject.org/streams/stable.json"
  request_headers = {
    Accept = "application/json"
  }
}

locals {
  coreos_builds = jsondecode(data.http.coreos_stable_builds.body).architectures
  image = {
    url      = local.coreos_builds[var.architecture].artifacts.hetzner.formats["raw.xz"].disk.location
    checksum = local.coreos_builds[var.architecture].artifacts.hetzner.formats["raw.xz"].disk.sha256
  }
}

source "hcloud" "fedora_base" {
  token       = var.token
  location    = var.location
  server_type = var.architecture == "aarch64" ? "cax11" : "cx22"

  image        = "fedora-42"
  rescue       = "linux64"
  ssh_username = "root"
  ssh_keys     = []
  user_data    = ""

  snapshot_name = "fedora_coreos"
  snapshot_labels = {
    "used"     = "homelab"
    "arch"     = var.architecture
    "checksum" = substr(local.image.checksum, 0, 63)
  }
}

build {
  sources = ["source.hcloud.fedora_base"]

  provisioner "shell" {
    inline = [
      "set -x",
      # Download image
      "curl -fsSL \"${local.image.url}\" -o /tmp/image.raw.xz",
      # Checksum verification
      "echo \"${local.image.checksum}  /tmp/image.raw.xz\" | sha256sum -c -",
      # If checksum is valid, extract the image
      "if [ $? -eq 0 ]; then",
      "    dd if=/tmp/image.raw.xz | xz -d | dd of=/dev/sda",
      "    sync",
      "    echo 'Image uploaded successfully!'",
      "else",
      "    echo 'Checksum verification failed!' && exit 1",
      "fi",
    ]
  }
}

