[Unit]
Description=Backup data using rsync
%{ if dependency != null }
Wants=network-online.target
After=network-online.target
Wants=${ dependency }
After=${ dependency }
%{ endif ~}

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'if [ -d ${ source }/backup ]; then btrfs subvolume delete ${source}/backup ; fi'
ExecStart=/usr/sbin/btrfs subvolume snapshot -r ${ source } ${ source }/backup
ExecStart=/usr/sbin/runuser -l ${ username } -c 'rsync -avP ${ source }/backup/ ${ destination }/'
ExecStart=/usr/sbin/btrfs subvolume delete ${ source }/backup

[Install]
WantedBy=multi-user.target
