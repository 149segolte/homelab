provider "butane" {}

# Prefix locals with `bu_` to avoid conflicts with other locals
locals {
  bu_user = {
    name   = local.user.name
    groups = local.user.groups
    uid    = local.user.uid
    ssh_authorized_keys = [
      local.user.ssh_key,
      local.terraform.ssh_key.public
    ]
  }

  bu_zram0 = {
    path = "/etc/systemd/zram-generator.conf"
    mode = "0644"
    contents = {
      inline = <<-EOT
        # This config file enables a /dev/zram0 device with the defaults
        [zram0]
      EOT
    }
  }

  bu_unprivileged_ports = {
    path = "/etc/sysctl.d/40-unprivileged-ports.conf"
    mode = "0644"
    contents = {
      inline = <<-EOT
        # Allow unprivileged users to bind to ports 443 and above
        net.ipv4.ip_unprivileged_port_start=443
      EOT
    }
  }

  bu_udp_buffer_sizes = {
    path = "/etc/sysctl.d/40-increase-udp-buffer-sizes.conf"
    mode = "0644"
    contents = {
      inline = <<-EOT
        # Increase the UDP buffer sizes to 7.5MB
        net.core.rmem_max=7500000
        net.core.wmem_max=7500000
      EOT
    }
  }

  bu_ip_forwarding = {
    path = "/etc/sysctl.d/99-forward.conf"
    mode = "0644"
    contents = {
      inline = <<-EOT
        # Enable IP forwarding
        net.ipv4.ip_forward=1
        net.ipv6.conf.all.forwarding=1
      EOT
    }
  }

  bu_ethtool_tlo_service = {
    name     = "ethtool-tlo.service"
    enabled  = true
    contents = <<-EOT
      [Unit]
      Description=Ethtool configuration to use transport layer offloads
      After=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/bin/env bash -c "ethtool -K $(ip -o route get 8.8.8.8 | cut -f 5 -d ' ') rx-udp-gro-forwarding on rx-gro-list off"

      [Install]
      WantedBy=multi-user.target
    EOT
  }

  bu_setup_service = {
    name     = "setup.service"
    enabled  = true
    contents = <<-EOT
      [Unit]
      Description=Initial Setup Service
      Wants=network-online.target
      After=network-online.target
      After=ignition-firstboot-complete.service
      ConditionPathExists=!/var/lib/%N.stamp
      ConditionFirstBoot=true

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=systemctl --global enable --now podman.socket
      ExecStart=loginctl enable-linger ${local.bu_user.name}
      ExecStart=/bin/touch /var/lib/%N.stamp

      [Install]
      WantedBy=multi-user.target
    EOT
  }

  bu_oci_update_service = {
    name     = "oci-update.service"
    enabled  = true
    contents = <<-EOT
      [Unit]
      Description=OCI Update Service
      After=network-online.target

      [Service]
      Type=oneshot
      ExecStart=rpm-ostree upgrade --reboot
    EOT
  }

  bu_oci_update_timer = {
    name     = "oci-update.timer"
    enabled  = true
    contents = <<-EOT
      [Unit]
      Description=OCI Update Timer

      [Timer]
      OnCalendar=daily
      RandomizedDelaySec=120

      [Install]
      WantedBy=timers.target
    EOT
  }
}

data "butane_config" "data_provider" {
  content = yamlencode({
    variant = "fcos"
    version = "1.6.0"
    passwd = {
      users = [local.bu_user]
    }

    storage = {
      disks = [{
        device     = "/dev/sdb"
        wipe_table = false
        partitions = [{
          label    = "data"
          size_mib = 0
          resize   = true
        }]
      }]

      filesystems = [{
        path            = "/var/mnt/data"
        device          = "/dev/disk/by-partlabel/data"
        format          = "btrfs"
        with_mount_unit = true
      }]

      files = [
        local.bu_zram0,
        {
          path = "/etc/hostname"
          mode = "0644"
          contents = {
            inline = "data_provider"
          }
        }
      ]

      directories = [{
        path = "/var/mnt/data"
        mode = "0770"
        user = {
          name = local.bu_user.name
        }
        group = {
          name = local.bu_user.name
        }
      }]
    }

    systemd = {
      units = [
        local.bu_setup_service,
        local.bu_oci_update_service,
        local.bu_oci_update_timer,
        {
          name    = "rebase.service"
          enabled = true
          contents = templatefile("${path.module}/templates/rebase.service.tftpl", {
            image_url = "${local.quay.base}/data_provider:latest"
          })
        }
      ]
    }
  })

  # files_dir = "files/data_provider"
  pretty = true
  strict = true
}

# output "data_provider" {
#   value = "config = ${data.butane_config.data_provider.ignition}"
# }

data "butane_config" "remote_node" {
  content = yamlencode({
    variant = "fcos"
    version = "1.6.0"
    passwd = {
      users = [local.bu_user]
    }

    storage = {
      disks = [{
        device     = "/dev/sdb"
        wipe_table = false
        partitions = [{
          label    = "data"
          size_mib = 0
          resize   = true
        }]
      }]

      filesystems = [{
        path            = "/var/mnt/data"
        device          = "/dev/disk/by-partlabel/data"
        format          = "btrfs"
        with_mount_unit = true
      }]

      files = [
        local.bu_zram0,
        {
          path = "/etc/hostname"
          mode = "0644"
          contents = {
            inline = "remote_node"
          }
        }
      ]

      directories = [{
        path = "/var/mnt/data"
        mode = "0770"
        user = {
          name = local.bu_user.name
        }
        group = {
          name = local.bu_user.name
        }
      }]
    }

    systemd = {
      units = [
        local.bu_setup_service,
        local.bu_oci_update_service,
        local.bu_oci_update_timer,
        {
          name    = "rebase.service"
          enabled = true
          contents = templatefile("${path.module}/templates/rebase.service.tftpl", {
            image_url = "${local.quay.base}/remote_node:latest"
          })
        }
      ]
    }
  })


  # files_dir = "files/remote_node"
  pretty = true
  strict = true
}

# output "remote_node" {
#   value = "config = ${data.butane_config.remote_node.ignition}"
# }

