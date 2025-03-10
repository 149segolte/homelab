[Unit]
Description=Configure system on first boot
Wants=network-online.target
After=network-online.target
%{ if package_install != null }After=${ package_install }%{ endif }
ConditionPathExists=!/var/lib/%N.stamp

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=300
%{ if ethtool != null }ExecStart=/bin/bash -c "/bin/systemctl enable --now ${ ethtool }"%{ endif }
%{ if tailscale != null ~}
ExecStart=/bin/systemctl enable --now tailscaled.service
ExecStart=/usr/bin/tailscale up --auth-key=${ tailscale.key }?ephemeral=true --advertise-tags=${ join(",", [for x in tailscale.tags: join("", ["tag:", x])]) } ${ join(" ", tailscale.flags) }
%{ endif ~}
%{ if commands != null ~}
%{ for command in commands ~}
ExecStart=${ command }
%{ endfor ~}
%{ endif ~}
ExecStart=/bin/touch /var/lib/%N.stamp
ExecStart=/bin/systemctl --no-block reboot

[Install]
WantedBy=multi-user.target
