#cloud-config
hostname: ${ hostname }
chpasswd:
  expire: false
users:
  - name: ${ username }
    groups: [${ groups }]
    uid: 1001
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
  - rsync
package_reboot_if_required: true
runcmd:
  - ["rc-update", "add", "nfs"]
  - ["rc-update", "add", "rsyncd"]
%{ for share in nfs_shares ~}
  - ["mkdir", "-p", "/mnt/data/${ share }"]
  - ["chown", "-R", "${ username }:${ username }", "/mnt/data/${ share }"]
%{ endfor ~}
power_state:
  delay: 1
  mode: reboot
  message: Rebooting after cloud-init
write_files:
  - path: /etc/exports
    defer: true
    content: |
%{ for share in nfs_shares ~}
      /mnt/data/${ share } 192.168.0.0/16(rw,sync,insecure,no_subtree_check,all_squash,anonuid=1001,anongid=1001)
%{ endfor ~}
