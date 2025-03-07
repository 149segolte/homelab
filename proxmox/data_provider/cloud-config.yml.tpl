#cloud-config
hostname: dataprovider
create_hostname_file: true
chpasswd:
  expire: false
users:
  - name: dataprovider
    groups: wheel, sudo
    doas: [permit nopass :wheel]
    ssh_authorized_keys:
      - ${ ssh_public_key }
packages:
  - qemu-guest-agent
  - qemu-guest-agent-openrc
  - nfs-utils
  - btrfs-progs
  - zstd
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
  - ["/dev/sdb1", "/mnt/data", "btrfs", "defaults,nofail,noatime,compress=zstd", "0", "0"]
bootcmd:
  - ["cloud-init-per", "always", "remove_exports", "echo '' > /etc/exports"]
  - ["cloud-init-per", "always", "load_shares", "mountpoint /mnt/data && echo '/mnt/data *(rw,no_root_squash,no_subtree_check)' > /etc/exports"]
  - ["cloud-init-per", "always", "reload_exports", "exportfs -rafv"]
runcmd:
  - rc-update add qemu-guest-agent
  - rc-update add nfs
  - rc-service qemu-guest-agent start
  - rc-service nfs start
