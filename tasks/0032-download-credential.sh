#!/bin/bash
# 0032-download-credential.sh
# Ganti kredensial unduh .bat agent lewat domain sesuai permintaan user.
# Username: Admin. Password TIDAK disimpan di repo: hanya hash APR1 di bawah.
set -euo pipefail

HT=/etc/nginx/ocsaeon-download.htpasswd
SECRET=/root/ocsaeon-secrets/download.env
DOMAIN=ocsaeon.itcnelita.com
FILE=Install-OCS-Agent-AEON-Internet.bat

cp -a "$HT" "/root/ocs-install/ocsaeon-download.htpasswd.bak-0032"
printf '%s\n' 'Admin:$apr1$Y6tTRvHE$gdid7YSDWpOXK0YdZ0il3.' > "$HT"
chown root:www-data "$HT"; chmod 640 "$HT"
( umask 077; printf '# kredensial unduh .bat (diatur user, task 0032)\nDL_USER=Admin\n# password: dipegang user, tidak disimpan di server\n' > "$SECRET" )
echo "user di htpasswd: $(cut -d: -f1 "$HT")"

nginx -t
systemctl reload nginx; sleep 2

fail=0
PUB="https://${DOMAIN}/aeon/private/${FILE}"
r1=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "$PUB")
r2=$(curl -s -m 20 -o /dev/null -w '%{http_code}' -u 'aeon-it:salah' "$PUB")
r3=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "http://192.168.100.122/aeon/private/${FILE}")
printf '%-36s -> %s (harap 401)\n' "domain tanpa password" "$r1"
printf '%-36s -> %s (harap 401)\n' "domain akun lama"      "$r2"
printf '%-36s -> %s (harap 200)\n' "LAN tanpa password"    "$r3"
[ "$r1" = 401 ] && [ "$r2" = 401 ] && [ "$r3" = 200 ] || fail=1
exit "$fail"
