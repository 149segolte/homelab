data "ignition_config" "remote_node" {
  disks       = [data.ignition_disk.remote_disk_layout.rendered]
  filesystems = [data.ignition_filesystem.remote_data_fs.rendered]
  users       = [data.ignition_user.user.rendered]
  files = concat(
    [
      data.ignition_file.remote_hostname.rendered,
      data.ignition_file.enable_zram0.rendered,
      data.ignition_file.allow_unprivileged_ports.rendered,
      data.ignition_file.increase_udp_buffer_sizes.rendered,
      data.ignition_file.allow_port_forwarding.rendered,
      data.ignition_file.remote_setup_script.rendered,
    ],
    [
      for x in concat(local.remote_containers, local.remote_volumes, local.remote_networks) : x.rendered
    ]
  )
  systemd = [
    data.ignition_systemd_unit.ethtool_config_tlo.rendered,
    data.ignition_systemd_unit.docker.rendered,
    data.ignition_systemd_unit.remote_data_fs_mount.rendered,
    data.ignition_systemd_unit.wait_for_tailscale.rendered,
    data.ignition_systemd_unit.remote_nfs_backup.rendered,
    data.ignition_systemd_unit.remote_backup_rsync.rendered,
    data.ignition_systemd_unit.remote_backup_rsync_timer.rendered,
    data.ignition_systemd_unit.remote_extra_packages.rendered,
    data.ignition_systemd_unit.remote_setup.rendered,
  ]
}

locals {
  remote_containers = [
    data.ignition_file.remote_container_traefik,
  ]
  remote_volumes = [
    data.ignition_file.remote_volume_traefik,
  ]
  remote_networks = [
    data.ignition_file.remote_network_services,
    data.ignition_file.remote_network_traefik,
  ]
}

data "ignition_file" "remote_hostname" {
  path = "/etc/hostname"
  mode = 420
  content {
    content = local.hetzner.node.name
  }
}

data "ignition_disk" "remote_disk_layout" {
  device     = "/dev/disk/by-id/coreos-boot-disk"
  wipe_table = false

  partition {
    number  = 4
    label   = "root"
    sizemib = 20480
    resize  = true
  }

  partition {
    label   = "data_containers"
    sizemib = 0
  }
}

data "ignition_filesystem" "remote_data_fs" {
  path   = "/var/srv/data"
  device = "/dev/disk/by-partlabel/${data.ignition_disk.remote_disk_layout.partition[0].label}"
  format = "btrfs"
}

data "ignition_systemd_unit" "remote_data_fs_mount" {
  name    = "${replace(substr(data.ignition_filesystem.remote_data_fs.path, 1, -1), "/", "-")}.mount"
  enabled = true
  content = templatefile("${path.module}/templates/services/fs.mount.tftpl", {
    type     = "disk"
    network  = null
    location = data.ignition_filesystem.remote_data_fs.device
    path     = data.ignition_filesystem.remote_data_fs.path
    format   = data.ignition_filesystem.remote_data_fs.format
  })
}

data "ignition_systemd_unit" "remote_nfs_backup" {
  name    = "${substr(replace(local.hetzner.node.backup_mount, "/", "-"), 1, -1)}.mount"
  enabled = false
  content = templatefile("${path.module}/templates/services/fs.mount.tftpl", {
    type     = "remote"
    network  = data.ignition_systemd_unit.wait_for_tailscale.name
    location = "${[for x in flatten(proxmox_virtual_environment_vm.data_provider[0].ipv4_addresses) : x if startswith(x, "192.168")][0]}:/mnt/data/${local.hetzner.node.name}"
    path     = local.hetzner.node.backup_mount
    format   = "nfs4"
  })
}

data "ignition_systemd_unit" "remote_backup_rsync" {
  name    = "backup-rsync.service"
  enabled = false
  content = templatefile("${path.module}/templates/services/backup_rsync.tftpl", {
    dependency  = data.ignition_systemd_unit.remote_nfs_backup.name
    source      = data.ignition_filesystem.remote_data_fs.path
    destination = local.hetzner.node.backup_mount
    username    = local.user.name
  })
}

data "ignition_systemd_unit" "remote_backup_rsync_timer" {
  name    = "${split(".", data.ignition_systemd_unit.remote_backup_rsync.name)[0]}.timer"
  enabled = false
  content = templatefile("${path.module}/templates/services/service.timer.tftpl", {
    service  = data.ignition_systemd_unit.remote_backup_rsync.name
    schedule = "*:0/30"
  })
}

data "ignition_systemd_unit" "remote_extra_packages" {
  name    = "package-layering.service"
  enabled = true
  content = templatefile("${path.module}/templates/services/extra_packages.tftpl", {
    packages = [
      "fish",
      "neovim",
      "tailscale"
    ]
  })
}

data "ignition_file" "remote_setup_script" {
  path = "/var/setup.sh"
  mode = 420
  content {
    content = templatefile("${path.module}/templates/setup.sh.tftpl", {
      ethtool_service = data.ignition_systemd_unit.ethtool_config_tlo.name
      tailscale = {
        key   = local.tailscale.hetzner_key
        tags  = ["homelab", "exitnode"]
        flags = ["--accept-dns=false", "--accept-routes", "--advertise-exit-node"]
      }
      nfs_backup_service = data.ignition_systemd_unit.remote_nfs_backup.name
      username           = local.user.name
      coreos_data_fs     = data.ignition_filesystem.remote_data_fs.path
      backup_mount       = local.hetzner.node.backup_mount
      backup_rsync_timer = data.ignition_systemd_unit.remote_backup_rsync_timer.name
      images             = [for x in local.remote_containers : x.path]
    })
  }
}

data "ignition_systemd_unit" "remote_setup" {
  name    = "setup.service"
  enabled = true
  content = templatefile("${path.module}/templates/services/setup.tftpl", {
    package_install = data.ignition_systemd_unit.remote_extra_packages.name
    setup_script    = data.ignition_file.remote_setup_script.path
  })
}

data "ignition_file" "remote_network_services" {
  path = "/home/${local.user.name}/.config/containers/networks/services.network"
  uid  = 1001
  gid  = 1001
  content {
    content = <<-EOT
      [Network]
    EOT
  }
}

data "ignition_file" "remote_container_traefik" {
  path = "/home/${local.user.name}/.config/containers/templates/services/traefik.container"
  uid  = 1001
  gid  = 1001
  content {
    content = templatefile("${path.module}/templates/quadlet.tftpl", {
      setup_service = "setup.service"
      name          = "traefik"
      image         = "docker.io/library/traefik:latest"
      description   = "Traefik reverse proxy"
      networks      = ["traefik", "services"]
      ports         = ["443:10443", "8080:8080"]
      volumes = [
        "/run/user/1001/podman/podman.sock:/var/run/docker.sock:z",
        "${data.ignition_filesystem.remote_data_fs.path}/traefik/acme.json:/letsencrypt/acme.json:z"
      ]
      environment = {
        TZ                       = local.hetzner.timezone
        CLOUDFLARE_EMAIL         = local.cloudflare.email
        CLOUDFLARE_DNS_API_TOKEN = local.cloudflare.api_token
      }
      exec = [
        "--global.checknewversion=true",
        "--global.sendanonymoususage=false",
        "--entrypoints.web.address=:10080",
        "--entrypoints.websecure.address=:10443",
        "--api.insecure=true",
        "--providers.docker=true",
        "--providers.docker.exposedbydefault=false",
        "--certificatesresolvers.cloudflare.acme.dnschallenge=true",
        "--certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare",
        "--certificatesresolvers.cloudflare.acme.caserver=${local.cloudflare.acme.url}",
        "--certificatesresolvers.cloudflare.acme.email=${local.cloudflare.acme.email}",
        "--certificatesresolvers.cloudflare.acme.storage=/letsencrypt/acme.json",
      ]
      labels = {
        "traefik.enable"                                         = "true"
        "traefik.http.routers.traefik-public.rule"               = "Host(`traefik-${local.domain.remote}`)"
        "traefik.http.routers.traefik-public.entrypoints"        = "web"
        "traefik.http.routers.traefik-public.tls"                = "false"
        "traefik.http.routers.traefik-public.service"            = "traefik"
        "traefik.http.routers.traefik.rule"                      = "Host(`traefik.${local.domain.remote}`)"
        "traefik.http.routers.traefik.entrypoints"               = "websecure"
        "traefik.http.routers.traefik.tls"                       = "true"
        "traefik.http.routers.traefik.tls.certresolver"          = "cloudflare"
        "traefik.http.routers.traefik.tls.domains[0].main"       = local.domain.remote
        "traefik.http.routers.traefik.tls.domains[0].sans"       = "*.${local.domain.remote}"
        "traefik.http.routers.traefik.service"                   = "traefik"
        "traefik.http.services.traefik.loadbalancer.server.port" = "8080"
      }
    })
  }
}

data "ignition_file" "remote_network_traefik" {
  path = "/home/${local.user.name}/.config/containers/networks/traefik.network"
  uid  = 1001
  gid  = 1001
  content {
    content = <<-EOT
      [Network]
    EOT
  }
}

data "ignition_file" "remote_volume_traefik" {
  path = "${data.ignition_filesystem.remote_data_fs.path}/traefik/acme.json"
  mode = 384
  uid  = 1001
  gid  = 1001
  content {
    content = ""
  }
}
