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
  most_recent       = true
}

data "ignition_config" "remote_node" {
  disks       = [jsonencode(local.coreos_disk_layout)]
  filesystems = [data.ignition_filesystem.coreos_data_fs.rendered]
  users       = [data.ignition_user.user.rendered]
  files = [
    data.ignition_file.remote_node_hostname.rendered,
    data.ignition_file.enable_zram0.rendered,
    data.ignition_file.allow_unprivileged_ports.rendered,
    data.ignition_file.increase_udp_buffer_sizes.rendered,
    data.ignition_file.tailscale_sysctl_config.rendered,
  ]
  systemd = [
    data.ignition_systemd_unit.tailscale_ethtool_config.rendered,
    data.ignition_systemd_unit.docker.rendered,
    data.ignition_systemd_unit.coreos_data_fs_mount.rendered,
    data.ignition_systemd_unit.wait_tailscale_up.rendered,
    data.ignition_systemd_unit.nfs_backup_mount.rendered,
    data.ignition_systemd_unit.backup_rsync.rendered,
    data.ignition_systemd_unit.backup_rsync_timer.rendered,
    data.ignition_systemd_unit.remote_node_extra_packages.rendered,
    data.ignition_systemd_unit.remote_node_setup.rendered,
  ]
}

resource "hcloud_server" "remote_node" {
  name        = local.hetzner.node.name
  server_type = local.hetzner.node.type
  location    = local.hetzner.node.location

  # Image is ignored, as we boot into rescue mode, but is a required field
  image    = [for x in data.hcloud_images.available_images.images : x.id if x.os_flavor == "fedora" && x.rapid_deploy == true][0]
  rescue   = "linux64"
  ssh_keys = [hcloud_ssh_key.primary_ssh_key.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  firewall_ids = [hcloud_firewall.restrict-access.id]

  connection {
    host        = self.ipv4_address
    timeout     = "4m" # Rough numbers: 30s provisioning, 1m15s rescue mode boot, 15s img verify, 45s img write, 15s reboot = 3m + leeway
    user        = "root"
    private_key = local.user.ssh.private_key
  }

  # Wait for the hetzner rescue mode to boot
  provisioner "remote-exec" {
    inline = ["echo 'Rescue mode booted!'"]
  }

  provisioner "remote-exec" {
    inline = [
      "set -x",
      "export COREOS_IMAGE=\"${local.os_releases.coreos.url}\"",
      "export COREOS_SHA256=\"${local.os_releases.coreos.checksum}\"",
      "curl -sL \"$COREOS_IMAGE\" -o /tmp/coreos.raw.xz",
      "echo \"$COREOS_SHA256  /tmp/coreos.raw.xz\" | sha256sum -c --status",
    ]
    on_failure = fail
  }

  # Copy config.ign
  provisioner "file" {
    content     = data.ignition_config.remote_node.rendered
    destination = "/root/config.ign"
  }

  provisioner "remote-exec" {
    inline = [
      "set -x",
      "xzcat /tmp/coreos.raw.xz | dd of=/dev/sda bs=4M",
      # Mount /boot partition
      "mount /dev/sda3 /mnt",
      "mkdir -p /mnt/ignition",
      "cp /root/config.ign /mnt/ignition/config.ign",
      "umount /mnt",
      "sync",
      "reboot"
    ]
  }

  # Wait for the server to reboot
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
