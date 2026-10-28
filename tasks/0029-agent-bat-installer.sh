#!/bin/bash
# 0029-agent-bat-installer.sh
# Buat Install-OCS-Agent-AEON.bat (berisi akun agent) dari template repo dan sajikan
# HANYA untuk LAN & Tailscale di http://<server>/aeon/private/Install-OCS-Agent-AEON.bat
# Akses lewat reverse proxy publik (Cloudflare, 192.168.100.110) DITOLAK.
#
# Rollback:
#   rm -rf /usr/share/ocsinventory-frontend/aeon/private
#   cp /root/ocs-install/ocs3-frontend-site.bak-0029 /etc/nginx/sites-available/ocsinventory-frontend && systemctl reload nginx
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$REPO_DIR/agent/Install-OCS-Agent-AEON.bat.template"
F=/usr/share/ocsinventory-frontend
PRIV="$F/aeon/private"
OUT="$PRIV/Install-OCS-Agent-AEON.bat"
SITE=/etc/nginx/sites-available/ocsinventory-frontend
LAN_SERVER=192.168.100.122
PROXY_IP=192.168.100.110
DOMAIN=ocsaeon.itcnelita.com
. /root/ocsaeon-secrets/ocs3-agent.env

SETUP=$(ls "$F"/aeon/agent/OCSInventory-Agent-Setup-Windows-*.exe | sort -V | tail -1)
SETUP_NAME=$(basename "$SETUP")
SETUP_SHA=$(sha256sum "$SETUP" | cut -d' ' -f1)
echo "installer: $SETUP_NAME  sha256=$SETUP_SHA"

echo "== Generate .bat"
install -d -m 750 -o root -g www-data "$PRIV"
sed -e "s|__OCS_SERVER__|${LAN_SERVER}|g" \
    -e "s|__AGENT_USER__|${OCS_AGENT_USER}|g" \
    -e "s|__AGENT_PASSWORD__|${OCS_AGENT_PWD}|g" \
    -e "s|__SETUP_NAME__|${SETUP_NAME}|g" \
    -e "s|__SETUP_SHA256__|${SETUP_SHA}|g" \
    -e 's/\r*$/\r/' "$TPL" > "$OUT"
chown root:www-data "$OUT"; chmod 640 "$OUT"
cp "$OUT" /root/ocsaeon-secrets/Install-OCS-Agent-AEON.bat; chmod 600 /root/ocsaeon-secrets/Install-OCS-Agent-AEON.bat
grep -q '__[A-Z_]*__' "$OUT" && { echo "!! placeholder belum terisi"; exit 1; } || echo "placeholder: semua terisi"
printf 'baris: %s, CRLF: %s\n' "$(wc -l < "$OUT")" "$(grep -c $'\r$' "$OUT")"
echo "-- isi (password disamarkan):"
sed -e "s|${OCS_AGENT_PWD}|********|g" "$OUT" | sed -n '9,16p' | tr -d '\r'

echo "== nginx: lokasi /aeon/private/ khusus LAN & Tailscale"
[ -f /root/ocs-install/ocs3-frontend-site.bak-0029 ] || cp "$SITE" /root/ocs-install/ocs3-frontend-site.bak-0029
python3 - "$SITE" "$PROXY_IP" <<'PY'
import sys, re
p, proxy = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r"\n    # \[ocsaeon 0029\].*?# \[/ocsaeon 0029\]\n", "\n", s, flags=re.S)
block = f"""
    # [ocsaeon 0029] file berisi akun agent: hanya LAN & Tailscale, tidak lewat proxy publik
    location ^~ /aeon/private/ {{
        if ($http_cf_connecting_ip) {{ return 403; }}
        if ($http_x_forwarded_for) {{ return 403; }}
        deny  {proxy};
        allow 127.0.0.1;
        allow 192.168.100.0/24;
        allow 100.64.0.0/10;
        deny  all;
        default_type application/octet-stream;
        add_header Content-Disposition "attachment" always;
        add_header Cache-Control "no-store" always;
    }}
    # [/ocsaeon 0029]
"""
marker = "    location / {"
assert marker in s, "location / tidak ditemukan"
s = s.replace(marker, block.lstrip("\n") + "\n" + marker, 1)
open(p, "w").write(s)
PY
if ! nginx -t 2>&1; then
  echo "!! nginx -t gagal, rollback"; cp /root/ocs-install/ocs3-frontend-site.bak-0029 "$SITE"; rm -f "$OUT"; exit 1
fi
systemctl reload nginx; sleep 1

echo "== Verifikasi akses"
fail=0
P=/aeon/private/Install-OCS-Agent-AEON.bat
code() { curl -s -m 15 -o /dev/null -w '%{http_code}' "$@"; }
r1=$(code "http://127.0.0.1$P")
r2=$(code "http://${LAN_SERVER}$P")
r3=$(code -H "CF-Connecting-IP: 1.2.3.4" "http://127.0.0.1$P")
r4=$(code "https://${DOMAIN}$P")
printf '%-36s -> %s (harap 200)\n' "lokal"                      "$r1"
printf '%-36s -> %s (harap 200)\n' "LAN ${LAN_SERVER}"          "$r2"
printf '%-36s -> %s (harap 403)\n' "dengan header Cloudflare"   "$r3"
printf '%-36s -> %s (harap 403)\n' "PUBLIK https://${DOMAIN}"   "$r4"
[ "$r1" = 200 ] && [ "$r2" = 200 ] && [ "$r3" = 403 ] || fail=1
if [ "$r4" = "200" ]; then
  echo "!! FILE BISA DIAKSES PUBLIK -> dihapus demi keamanan"; rm -f "$OUT"; fail=1
fi
curl -s "http://127.0.0.1$P" | cmp -s - "$OUT" && echo "isi file tersaji utuh: OK" || fail=1
echo "-- installer exe tetap tersedia: $(code "http://${LAN_SERVER}/aeon/agent/${SETUP_NAME}")"
exit "$fail"
