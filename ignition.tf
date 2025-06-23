data "ignition_user" "user" {
  name                = local.user.name
  ssh_authorized_keys = [local.user.ssh_key]
  groups              = local.user.groups
}

data "ignition_file" "enable_zram0" {
  path = "/etc/systemd/zram-generator.conf"
  mode = 420
  content {
    content = "# This config file enables a /dev/zram0 device with the defaults\n[zram0]\n"
  }
}

data "ignition_file" "allow_unprivileged_ports" {
  path = "/etc/sysctl.d/40-unprivileged-ports.conf"
  mode = 420
  content {
    content = <<-EOT
      # Allow unprivileged users to bind to ports 443 and above
      net.ipv4.ip_unprivileged_port_start=443
    EOT
  }
}

data "ignition_file" "increase_udp_buffer_sizes" {
  path = "/etc/sysctl.d/40-increase-udp-buffer-sizes.conf"
  mode = 420
  content {
    content = <<-EOT
      # Increase the UDP buffer sizes to 7.5MB
      net.core.rmem_max=7500000
      net.core.wmem_max=7500000
    EOT
  }
}

data "ignition_file" "allow_port_forwarding" {
  path = "/etc/sysctl.d/99-forward.conf"
  mode = 420
  content {
    content = <<-EOT
      # Enable IP forwarding
      net.ipv4.ip_forward=1
      net.ipv6.conf.all.forwarding=1
    EOT
  }
}

data "ignition_systemd_unit" "ethtool_config_tlo" {
  name    = "ethtool.service"
  enabled = false
  content = file("${path.module}/templates/services/ethtool.service")
}

data "ignition_systemd_unit" "docker" {
  name = "docker.service"
  mask = true
}

data "ignition_systemd_unit" "wait_for_tailscale" {
  name    = "wait-tailscale-up.service"
  enabled = true
  content = templatefile("${path.module}/templates/services/ping_network.tftpl", {
    dependency = "tailscaled.service"
    address    = "192.168.2.1"
  })
}
