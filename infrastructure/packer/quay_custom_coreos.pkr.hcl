packer {
  required_plugins {
    docker = {
      source  = "github.com/hashicorp/docker"
      version = "~> 1.1"
    }
  }
}

variable "quay_username" {
  description = "Username for Quay.io"
  type        = string
}

variable "quay_password" {
  description = "Password for Quay.io"
  type        = string
  sensitive   = true
}

variable "quay_image_url" {
  description = "Quay.io image URL for the container"
  type        = string
}

variable "quay_image_tags" {
  description = "List of tags for the Quay.io image (JSON encoded)"
  type        = string
}

variable "commands" {
  description = "List of docker commands to run in the container (JSON encoded)"
  type        = string
  sensitive   = true
}

source "docker" "coreos" {
  image   = "quay.io/fedora/fedora-coreos:stable"
  changes = jsondecode(var.commands)
  commit  = true
}

build {
  sources = ["source.docker.coreos"]

  post-processors {
    post-processor "docker-tag" {
      repository = var.quay_image_url
      tags       = jsondecode(var.quay_image_tags)
    }
    post-processor "docker-push" {
      login          = true
      login_server   = "quay.io"
      login_username = var.quay_username
      login_password = var.quay_password
    }
  }
}

