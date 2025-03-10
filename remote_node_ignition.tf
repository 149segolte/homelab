data "ignition_user" "user" {
  name                = local.user.name
  ssh_authorized_keys = [local.user.ssh.public_key]
  groups              = local.user.groups
}

data "ignition_file" "remote_node_hostname" {
  path = "/etc/hostname"
  mode = 420
  content {
    content = local.hetzner.node.name
  }
}

data "ignition_file" "enable_zram0" {
  path = "/etc/systemd/zram-generator.conf"
  mode = 420
  content {
    content = "# This config file enables a /dev/zram0 device with the defaults\n[zram0]\n"
  }
}

data "ignition_file" "tailscale_sysctl_config" {
  path = "/etc/sysctl.d/99-tailscale.conf"
  mode = 420
  content {
    content = "net.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1\n"
  }
}

data "ignition_systemd_unit" "tailscale_ethtool_config" {
  name    = "ethtool@.service"
  enabled = false
  content = file("${path.module}/systemd/tailscale_ethtool.service")
}

data "ignition_systemd_unit" "docker" {
  name = "docker.service"
  mask = true
}

# TODO: remove when provider is fixed https://github.com/community-terraform-providers/terraform-provider-ignition/issues/85
locals {
  coreos_disk_layout = {
    device    = "/dev/disk/by-id/coreos-boot-disk"
    wipeTable = false
    partitions = [
      {
        number  = 4
        label   = "root"
        sizeMiB = 20480
        resize  = true
      },
      {
        label   = "data_containers"
        sizeMiB = 0
      }
    ]
  }
}

data "ignition_filesystem" "coreos_data_fs" {
  path   = "/var/srv/data"
  device = "/dev/disk/by-partlabel/${local.coreos_disk_layout.partitions[1].label}"
  format = "btrfs"
}

data "ignition_systemd_unit" "coreos_data_fs_mount" {
  name    = "${replace(substr(data.ignition_filesystem.coreos_data_fs.path, 1, -1), "/", "-")}.mount"
  enabled = true
  content = templatefile("${path.module}/systemd/fs.mount.tpl", {
    type     = "disk"
    network  = null
    location = data.ignition_filesystem.coreos_data_fs.device
    path     = data.ignition_filesystem.coreos_data_fs.path
    format   = data.ignition_filesystem.coreos_data_fs.format
  })
}

data "ignition_systemd_unit" "wait_tailscale_up" {
  name    = "wait-tailscale-up.service"
  enabled = true
  content = templatefile("${path.module}/systemd/network_reachable.service.tpl", {
    dependency = "tailscaled.service"
    address    = "192.168.2.1"
  })
}

data "ignition_systemd_unit" "nfs_backup_mount" {
  name    = "${substr(replace(local.hetzner.node.backup_mount, "/", "-"), 1, -1)}.mount"
  enabled = false
  content = templatefile("${path.module}/systemd/fs.mount.tpl", {
    type     = "remote"
    network  = data.ignition_systemd_unit.wait_tailscale_up.name
    location = "${[for x in flatten(proxmox_virtual_environment_vm.data_provider[0].ipv4_addresses) : x if startswith(x, "192.168")][0]}:/mnt/data/${local.hetzner.node.name}"
    path     = local.hetzner.node.backup_mount
    format   = "nfs4"
  })
}

data "ignition_systemd_unit" "backup_rsync" {
  name    = "backup-rsync.service"
  enabled = false
  content = templatefile("${path.module}/systemd/backup_rsync.service.tpl", {
    dependency  = data.ignition_systemd_unit.nfs_backup_mount.name
    source      = data.ignition_filesystem.coreos_data_fs.path
    destination = local.hetzner.node.backup_mount
    username    = local.user.name
  })
}

data "ignition_systemd_unit" "backup_rsync_timer" {
  name    = "${split(".", data.ignition_systemd_unit.backup_rsync.name)[0]}.timer"
  enabled = false
  content = templatefile("${path.module}/systemd/service.timer.tpl", {
    service  = data.ignition_systemd_unit.backup_rsync.name
    schedule = "*:0/30"
  })
}

data "ignition_systemd_unit" "remote_node_extra_packages" {
  name    = "package-layering.service"
  enabled = true
  content = templatefile("${path.module}/systemd/extra_packages.service.tpl", {
    packages = [
      "fish",
      "neovim",
      "tailscale"
    ]
  })
}

data "ignition_systemd_unit" "remote_node_setup" {
  name    = "setup.service"
  enabled = true
  content = templatefile("${path.module}/systemd/coreos_setup.service.tpl", {
    package_install = data.ignition_systemd_unit.remote_node_extra_packages.name
    ethtool = replace(
      data.ignition_systemd_unit.tailscale_ethtool_config.name, "@", "@$(ip -o route get 8.8.8.8 | cut -f 5 -d ' ')"
    )
    tailscale = {
      key   = local.tailscale.hetzner_key
      tags  = ["homelab", "exitnode"]
      flags = ["--accept-dns=false", "--accept-routes", "--advertise-exit-node"]
    }
    commands = [
      "/bin/systemctl enable --now podman.socket",
      "/bin/systemctl enable --now ${data.ignition_systemd_unit.nfs_backup_mount.name}",
      "/usr/bin/chown -R ${local.user.name}:${local.user.name} ${data.ignition_filesystem.coreos_data_fs.path}",
      "/usr/sbin/runuser -l ${local.user.name} -c 'rsync -avP ${local.hetzner.node.backup_mount}/ ${data.ignition_filesystem.coreos_data_fs.path}/'",
      "/bin/systemctl enable --now ${data.ignition_systemd_unit.backup_rsync_timer.name}",
    ]
  })
}
