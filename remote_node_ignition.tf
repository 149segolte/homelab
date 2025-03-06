data "ignition_config" "remote_node" {
  users = [data.ignition_user.user.rendered]
  files = [
    data.ignition_file.hostname.rendered,
    data.ignition_file.zram0.rendered,
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
