#!/bin/bash
# 0031-bat-download-via-domain.sh
# File .bat agent bisa diunduh lewat domain dengan password (HTTP Basic Auth, di atas HTTPS Cloudflare).
#   - LAN 192.168.100.0/24 & Tailscale: tanpa password (seperti sebelumnya)
#   - Lewat reverse proxy publik (192.168.100.110 / Cloudflare): wajib username+password
# Kredensial download disimpan di /root/ocsaeon-secrets/download.env (tidak dicetak).
#
# Rollback: cp /root/ocs-install/ocs3-frontend-site.bak-0031 /etc/nginx/sites-available/ocsinventory-frontend && systemctl reload nginx
set -euo pipefail

SITE=/etc/nginx/sites-available/ocsinventory-frontend
HT=/etc/nginx/ocsaeon-download.htpasswd
SECRET=/root/ocsaeon-secrets/download.env
PROXY_IP=192.168.100.110
DOMAIN=ocsaeon.itcnelita.com
PRIV=/usr/share/ocsinventory-frontend/aeon/private
FILE=Install-OCS-Agent-AEON-Internet.bat

echo "== Kredensial download"
if [ ! -f "$SECRET" ]; then
  ( umask 077; printf 'DL_USER=aeon-it\nDL_PWD=%s\n' "$(openssl rand -hex 10)" > "$SECRET" )
fi
chmod 600 "$SECRET"; . "$SECRET"
printf '%s:%s\n' "$DL_USER" "$(openssl passwd -apr1 "$DL_PWD")" > "$HT"
chown root:www-data "$HT"; chmod 640 "$HT"
echo "user download: $DL_USER (password di $SECRET)"

echo "== nginx: /aeon/private/ = LAN/Tailscale bebas, selain itu wajib password"
[ -f /root/ocs-install/ocs3-frontend-site.bak-0031 ] || cp "$SITE" /root/ocs-install/ocs3-frontend-site.bak-0031
python3 - "$SITE" "$PROXY_IP" "$HT" <<'PY'
import sys, re
p, proxy, ht = sys.argv[1:4]
s = open(p).read()
s = re.sub(r"    # \[ocsaeon 00(29|31)\].*?# \[/ocsaeon 00(29|31)\]\n", "", s, flags=re.S)
block = f"""    # [ocsaeon 0031] file berisi akun agent: LAN & Tailscale bebas, lewat proxy publik wajib password
    location ^~ /aeon/private/ {{
        satisfy any;
        deny  {proxy};
        allow 127.0.0.1;
        allow 192.168.100.0/24;
        allow 100.64.0.0/10;
        deny  all;
        auth_basic "AEON - unduh installer OCS Agent";
        auth_basic_user_file {ht};
        default_type application/octet-stream;
        add_header Content-Disposition "attachment" always;
        add_header Cache-Control "private, no-store, max-age=0" always;
    }}
    # [/ocsaeon 0031]
"""
marker = "    location / {"
assert marker in s
s = s.replace(marker, block + marker, 1)
open(p, "w").write(s)
PY
if ! nginx -t 2>&1; then
  echo "!! nginx -t gagal, rollback"; cp /root/ocs-install/ocs3-frontend-site.bak-0031 "$SITE"; exit 1
fi
systemctl reload nginx; sleep 2

echo "== Verifikasi"
fail=0
PUB="https://${DOMAIN}/aeon/private/${FILE}"
c() { curl -s -m 20 -o /dev/null -w '%{http_code}' "$@"; }
r1=$(c "$PUB")
r2=$(c -u "${DL_USER}:salah-password" "$PUB")
r3=$(curl -s -m 30 -D /tmp/ocsaeon-h.txt -o /tmp/ocsaeon-b.bat -w '%{http_code}' -u "${DL_USER}:${DL_PWD}" "$PUB")
r4=$(c "$PUB")
r5=$(c "http://192.168.100.122/aeon/private/${FILE}")
printf '%-44s -> %s (harap 401)\n' "domain tanpa password"            "$r1"
printf '%-44s -> %s (harap 401)\n' "domain password salah"            "$r2"
printf '%-44s -> %s (harap 200)\n' "domain password benar"            "$r3"
printf '%-44s -> %s (harap 401, bukan dari cache)\n' "domain tanpa password (setelah unduh)" "$r4"
printf '%-44s -> %s (harap 200)\n' "LAN tanpa password"               "$r5"
echo "-- header Cloudflare: $(grep -i -E '^(cf-cache-status|cache-control|content-disposition):' /tmp/ocsaeon-h.txt | tr -d '\r' | tr '\n' ' ')"
cmp -s /tmp/ocsaeon-b.bat "$PRIV/$FILE" && echo "isi file lewat domain utuh: OK" || { echo "!! isi berbeda"; fail=1; }
[ "$r1" = 401 ] && [ "$r2" = 401 ] && [ "$r3" = 200 ] && [ "$r4" = 401 ] && [ "$r5" = 200 ] || fail=1
if [ "$r4" = 200 ] || [ "$r1" = 200 ]; then
  echo "!! file bisa diunduh tanpa password lewat domain -> akses domain ditutup"
  cp /root/ocs-install/ocs3-frontend-site.bak-0031 "$SITE" && systemctl reload nginx
fi
rm -f /tmp/ocsaeon-h.txt /tmp/ocsaeon-b.bat
exit "$fail"
