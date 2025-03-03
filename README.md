# homelab

This repository contains the terraform scripts to provision my homelab. The homelab is self contained on a single laptop running Proxmox and is able to perform the following tasks:

- Connect to any WiFi network and create a secondary `AP-mode` interface to host a WiFi network.
  - Requires a WiFi adapter that supports both `AP` and `managed` modes. [ArchWiki#Software_access_point](https://wiki.archlinux.org/title/Software_access_point#Wireless_client_and_software_AP_with_a_single_Wi-Fi_device)
  - Use `hostapd` to configure the `AP` interface.
- Run PfSense as a VM to act as a router and firewall, with WAN as the primary WiFi interface, LAN as the secondary `AP` interface, and LAN2 as the internal network for VMs.
  - Use `/etc/network/interfaces` to configure `vmbr0` to NAT over `wlan0`, making `vmbr0` the WAN interface.
  - Create `vmbr1` and use `bridge=vmbr1` option in `hostapd` to redirect traffic from `AP` interface to `vmbr1`, making `vmbr1` the LAN interface.
  - Create `vmbr2` and use it as the internal network for VMs, making `vmbr2` the LAN2 interface.
  - Runs `tailscale` package to advertise the internal network to the tailscale network.
- Run a minimal Alpine VM to act as a network storage provider with backups to external storage.
  - Has a single disk image attached to it from a SSD storage pool.
  - The disk image is backed up to an external storage pool by proxmox on daily and weekly schedules with a retention policy.
  - Shares chunks of the disk image over the network using `nfs` to various ephemeral/immutable VMs (like Fedora CoreOS etc.) for their storage needs.
  - Maintains a copy of contents of the disk image on the external storage pool using `rsync` on a hourly schedule.
- Run Fedora CoreOS to serve the homelab services.
  - Runs `traefik` as a reverse proxy to route traffic to various services.
  - `traefik` is configured with two entrypoints, one for `http` and one for `https`.
  - Exposes `https` entrypoint to the internal network with `letsencrypt` certificates.
  - Uses `cloudflared` to tunnel traffic from a public domain to the `http` entrypoint as tls is terminated at `cloudflare`.
- Has a primary VM to run Steam and LM Studio.
  - Uses `vfio` to passthrough the dGPU to the VM.
  - Passes built-in `eDP` display to the VM.
  - Passes keyboard, trackpad, and USB ports to the VM.
- Has a secondary VM as a development environment.

## Prerequisites

Requires the following to be installed on the runner machine:

- `hashicorp/terraform` cli to run the terraform scripts.
- `hashicorp/vault` cli to store secrets.

Note: To persist data a remote storage box is used, but if network has a cap or bandwidth is an issue, while experimenting it is recommended to use a local storage setup as you will be creating and destroying a lot of infrastructure.

## Usage

There are certain steps that need to be performed before running the terraform scripts, ensure that the following things are setup:

- Setup BIOS settings for target machine.
  - Enable virtualization
  - Enable IOMMU (if using dGPU passthrough)
  - Disable integrated graphics (if using dGPU passthrough and built-in display)
  - Set boot password (Optional)

- Install Standard Proxmox VE on the target machine.
  - Disable `pve-enterprise` repository and enable `pve-no-subscription` repository.
  - Update the system and reboot.
  - Setup network interfaces as required.
  - Create required storage pools. (`bpg/terraform-provider-proxmox` does not support creating storage pools yet)

- Create a `vault` server to store secrets on the runner machine.
  - Homebrew install `vault` cli.
  - Run `vault server -config=vault.hcl` to start the vault server.
  - Use the web UI to setup the vault server, create a `kv2` secret engine and a `userpass` auth method.
  - Load required secrets into the vault server as defined below.

- Create a `terraform.tfvars` file with the following variables:
  ```hcl
  vault_username = "username"
  vault_password = "password"
  vault_cert = "path/to/cert.pem" # Used to verify the vault server.
  internal_network = false # Will be false for first provisioning, but can be set to true for subsequent runs after PfSense is setup.
  ```

### Secrets

Assuming base kv2 store path as `homelab/terraform`. The following secrets need to be loaded into the vault server:

- `homelab/terraform/proxmox`
  ```json
  {
    "endpoint_external": "https://<external_ip>:8006/",
    "endpoint_internal": "https://<internal_domain>:8006/",
    "username": "root@pam",
    "password": "password",
    "node": "pve"
  }
  ```
