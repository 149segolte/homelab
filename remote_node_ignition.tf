data "ignition_config" "remote_node" {
  users = [data.ignition_user.user.rendered]
  files = [
    data.ignition_file.hostname.rendered,
    data.ignition_file.zram0.rendered,
    data.ignition_file.sysctl_tailscale.rendered,
  ]
  systemd = [
    data.ignition_systemd_unit.ethtool.rendered,
    data.ignition_systemd_unit.docker.rendered,
    data.ignition_systemd_unit.setup.rendered,
  ]
}

data "ignition_user" "user" {
  name                = local.remote_ignition.user.name
  password_hash       = local.remote_ignition.user.password_hash
  ssh_authorized_keys = [local.ssh.public_key]
  groups              = local.remote_ignition.user.groups
}

data "ignition_file" "hostname" {
  path = "/etc/hostname"
  mode = 420
  content {
    content = local.remote_ignition.hostname
  }
}

data "ignition_file" "zram0" {
  path = "/etc/systemd/zram-generator.conf"
  mode = 420
  content {
    content = "# This config file enables a /dev/zram0 device with the defaults\n[zram0]\n"
  }
}

data "ignition_file" "sysctl_tailscale" {
  path = "/etc/sysctl.d/99-tailscale.conf"
  mode = 420
  content {
    content = "net.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1\n"
  }
}

data "ignition_systemd_unit" "ethtool" {
  name    = "ethtool@.service"
  enabled = false
  content = <<-EOT
    [Unit]
    Description=Ethtool configuration to use transport layer offloads
    Wants=network-online.target
    After=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/sbin/ethtool -K %i rx-udp-gro-forwarding on rx-gro-list off

    [Install]
    WantedBy=multi-user.target
  EOT
}

data "ignition_systemd_unit" "docker" {
  name = "docker.service"
  mask = true
}

data "ignition_systemd_unit" "setup" {
  name    = "setup.service"
  enabled = true
  content = <<-EOT
    [Unit]
    Description=Configure system on first boot
    Wants=network-online.target
    After=network-online.target
    ConditionPathExists=!/var/lib/%N.stamp

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/bin/bash -c "/bin/systemctl enable --now ethtool@$(ip -o route get 8.8.8.8 | cut -f 5 -d ' ').service"
    ExecStart=/bin/systemctl enable --now podman.socket
    ExecStart=/bin/touch /var/lib/%N.stamp

    [Install]
    WantedBy=multi-user.target
  EOT
}
