provider "hcloud" {
  token         = local.hetzner.client.token
  poll_interval = local.hetzner.client.poll_interval
}

resource "hcloud_ssh_key" "primary_ssh_key" {
  name       = "primary_ssh_key"
  public_key = local.ssh.public_key

  labels = {
    "used" = "homelab"
  }
}

resource "hcloud_firewall" "block-inbound" {
  name = "block-inbound"

  labels = {
    "used" = "homelab"
  }
}

data "hcloud_images" "available_images" {
  with_architecture = ["arm"]
  with_status       = ["available"]
  most_recent       = true
}

locals {
  fedora_image = [for x in data.hcloud_images.available_images.images : x.id if x.os_flavor == "fedora" && x.rapid_deploy == true][0]
}

resource "hcloud_server" "remote_node" {
  name        = local.hetzner.node.name
  server_type = local.hetzner.node.type
  location    = local.hetzner.node.location

  # Image is ignored, as we boot into rescue mode, but is a required field
  image    = local.fedora_image
  rescue   = "linux64"
  ssh_keys = [hcloud_ssh_key.primary_ssh_key.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  connection {
    host        = self.ipv4_address
    timeout     = "5m"
    user        = "root"
    private_key = local.ssh.private_key
    agent       = provider::assert::null(local.ssh.private_key) ? true : false
  }

  # Wait for the server to be available
  provisioner "remote-exec" {
    inline = ["echo 'connected!'"]
  }

  # Copy config.yaml
  provisioner "file" {
    content     = file("config.yaml")
    destination = "/root/config.yaml"
  }

  # Only do this if the server has enough resources
  provisioner "remote-exec" {
    inline = [
      "set -x",
      "apt update",
      "apt install podman -y",
      "update-alternatives --set iptables /usr/sbin/iptables-legacy",
      "podman run --pull=always --privileged --rm -v /dev:/dev -v /run/udev:/run/udev -v .:/data -w /data quay.io/coreos/coreos-installer:release install /dev/sda -i config.ign",
      "reboot"
    ]
  }

  # Wait for the server to be available
  provisioner "remote-exec" {
    inline = ["echo 'connected!'"]
  }

  labels = {
    "used" = "homelab"
  }
}
