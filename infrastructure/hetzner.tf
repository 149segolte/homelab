provider "hcloud" {
  token         = local.hetzner.client.token
  poll_interval = local.hetzner.client.poll_interval
}

resource "hcloud_ssh_key" "homelab_primary" {
  name       = "homelab-primary"
  public_key = local.user.ssh_key

  labels = {
    "used" = "homelab"
  }
}

resource "hcloud_firewall" "restricted-access" {
  name = "restricted-access"
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  } # Allow ICMP (ping)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  } # Allow SSH
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  } # Allow Tailscale
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  } # Allow HTTPS
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  } # Allow HTTP/3

  labels = {
    "used" = "homelab"
  }
}

data "hcloud_image" "coreos" {
  with_architecture = "arm"
  with_status       = ["available"]
  with_selector     = "used=homelab"
  most_recent       = true

  depends_on = [packer_image.coreos_hetzner]
}

resource "hcloud_server" "remote_node" {
  name        = local.hetzner.node.name
  server_type = local.hetzner.node.type
  location    = local.hetzner.location

  image     = data.hcloud_image.coreos.id
  ssh_keys  = [hcloud_ssh_key.homelab_primary.id]
  user_data = data.butane_config.remote_node.ignition

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  firewall_ids = [hcloud_firewall.restricted-access.id]

  # Wait for the server to boot
  provisioner "remote-exec" {
    connection {
      host        = self.ipv4_address
      timeout     = "1m"
      user        = local.user.name
      private_key = local.terraform.ssh_key.private
    }

    inline = ["echo 'CoreOS terraform check: success'"]
  }

  labels = {
    "used" = "homelab"
  }
}
