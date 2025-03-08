#cloud-config
hostname: ${ hostname }
chpasswd:
  expire: false
users:
  - name: ${ username }
    groups: [${ groups }]
    doas:
      - permit nopass ${ username } as root
    ssh_authorized_keys:
      - ${ ssh_public_key }
disk_setup:
  /dev/sdb:
    table_type: gpt
    layout: true
    overwrite: false
fs_setup:
  - label: data
    filesystem: btrfs
    device: /dev/sdb1
    overwrite: false
mounts:
  - [swap]
  - [
      "/dev/sdb1",
      "/mnt/data",
      "btrfs",
      "defaults,nofail,noatime,compress=zstd",
      "0",
      "0",
    ]
packages:
  - nfs-utils
package_reboot_if_required: true
write_files:
  - path: /etc/exports
    content: |
      /mnt/data *(rw,sync,no_subtree_check)
    defer: true
runcmd:
  - ["rc-update", "add", "nfs"]
power_state:
  delay: 1
  mode: reboot
  message: Rebooting after cloud-init
