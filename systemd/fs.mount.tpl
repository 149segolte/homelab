[Unit]
Description=Mount filesystem at boot
%{ if type == "disk" ~}
Requires=systemd-fsck@${ replace(replace(substr(location, 1, -1), "-", "\\x2d"), "/", "-") }.service
After=systemd-fsck@${ replace(replace(substr(location, 1, -1), "-", "\\x2d"), "/", "-") }.service
%{ endif ~}
%{ if network != null ~}
Wants=network-online.target
After=network-online.target
Wants=${ network }
After=${ network }
%{ endif ~}

[Mount]
%{ if type == "remote" ~}
TimeoutSec=60
%{ endif ~}
What=${ location }
Where=${ path }
Type=${ format }

[Install]
RequiredBy=local-fs.target
