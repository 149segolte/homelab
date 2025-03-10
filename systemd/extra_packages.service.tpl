[Unit]
Description=Layer packages on top of the base image
Wants=network-online.target
After=network-online.target
# We run before `zincati.service` to avoid conflicting rpm-ostree
# transactions.
Before=zincati.service
ConditionPathExists=!/var/lib/%N.stamp

[Service]
Type=oneshot
RemainAfterExit=yes
# `--allow-inactive` ensures that rpm-ostree does not return an error
# if the package is already installed. This is useful if the package is
# added to the root image in a future Fedora CoreOS release as it will
# prevent the service from failing.
ExecStart=/usr/bin/rpm-ostree install -y --allow-inactive ${ join(" ", packages) }
ExecStart=/bin/touch /var/lib/%N.stamp
ExecStart=/bin/systemctl --no-block reboot

[Install]
WantedBy=multi-user.target
