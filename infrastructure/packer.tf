provider "packer" {}

data "packer_version" "ver" {}

data "packer_files" "coreos_hetzner_upload" {
  file = "${path.module}/packer/coreos_hetzner_upload.pkr.hcl"
}

data "packer_files" "quay_custom_coreos" {
  file = "${path.module}/packer/quay_custom_coreos.pkr.hcl"
}

resource "packer_image" "coreos_hetzner" {
  file = data.packer_files.coreos_hetzner_upload.file

  variables = {
    location     = local.hetzner.location
    architecture = startswith(local.hetzner.node.type, "cax") ? "aarch64" : "x86_64"
  }

  sensitive_variables = {
    token = local.hetzner.client.token
  }

  force = true
  triggers = {
    packer = data.packer_version.ver.version
    hash   = data.packer_files.coreos_hetzner_upload.files_hash
  }
}

resource "packer_image" "data_provider_oci" {
  file = data.packer_files.quay_custom_coreos.file

  variables = {
    quay_image_url  = "${local.quay.base}/data_provider"
    quay_image_tags = jsonencode(["latest"])
    quay_username   = local.quay.username
  }

  sensitive_variables = {
    quay_password = local.quay.password
    commands = jsonencode(concat(
      ["RUN rpm-ostree install -y qemu-guest-agent && ostree container commit"],
      # [for c in local.containers : "ADD ${path.module}/../containers/${c.name}/quadlets /etc/containers/systemd/users/${var.user_id}/${c.name}"],
      # ["RUN ostree container commit"],
      # [for c in local.containers : "ADD ${var.base_search_path}/${c.name}/config /etc/containers/${c.name}"],
      # ["RUN ostree container commit"],
      # [for c in local.containers : "RUN podman pull ${c.image} && ostree container commit"]
    ))
  }

  force = true
  triggers = {
    packer = data.packer_version.ver.version
    hash   = data.packer_files.quay_custom_coreos.files_hash
  }
}

