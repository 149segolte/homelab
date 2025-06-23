provider "hcloud" {
  token         = local.hetzner.client.token
  poll_interval = local.hetzner.client.poll_interval
}

resource "hcloud_ssh_key" "primary_ssh_key" {
  name       = "primary_ssh_key"
  public_key = local.user.ssh.public_key

  labels = {
    "used" = "homelab"
  }
}

resource "hcloud_firewall" "restrict-access" {
  name = "restrict-access"
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  labels = {
    "used" = "homelab"
  }
}

data "hcloud_images" "available_images" {
  with_architecture = ["arm"]
  with_status       = ["available"]
  with_selector     = "used=homelab"
  most_recent       = true

  lifecycle {
    postcondition {
      condition     = length(self.images) > 0
      error_message = "No images available in the hetzner environment"
    }
  }
}

resource "hcloud_server" "remote_node" {
  name        = local.hetzner.node.name
  server_type = local.hetzner.node.type
  location    = local.hetzner.node.location

  image     = data.hcloud_images.available_images.images[0].id
  ssh_keys  = [hcloud_ssh_key.primary_ssh_key.id]
  user_data = data.ignition_config.remote_node.rendered

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  firewall_ids = [hcloud_firewall.restrict-access.id]

  # Wait for the server to boot
  provisioner "remote-exec" {
    connection {
      host        = self.ipv4_address
      timeout     = "1m"
      user        = local.user.name
      private_key = local.user.ssh.private_key
    }

    inline = ["echo 'CoreOS booted!'"]
  }

  labels = {
    "used" = "homelab"
  }
}
