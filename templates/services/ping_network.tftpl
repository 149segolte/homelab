[Unit]
Description=Wait for network to be reachable
Wants=network-online.target
After=network-online.target
%{ if dependency != null ~}
Wants=${ dependency }
After=${ dependency }
%{ endif ~}

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=60
ExecStart=/usr/bin/bash -c "until ping -c1 '${ address }'; do sleep 1; done"

[Install]
WantedBy=multi-user.target
