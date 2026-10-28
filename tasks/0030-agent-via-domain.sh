#!/bin/bash
# 0030-agent-via-domain.sh
# Agent untuk PC di luar LAN: kirim lewat https://ocsaeon.itcnelita.com/api (Cloudflare).
# 1) Uji alur agent lewat domain publik (api-check, token, myaccount, asset/configs)
#    termasuk User-Agent agent (Dart) supaya ketahuan kalau diblok anti-bot Cloudflare
# 2) Generate 2 varian .bat dari template:
#      Install-OCS-Agent-AEON.bat           -> LAN   (http://192.168.100.122:8081)
#      Install-OCS-Agent-AEON-Internet.bat  -> domain (https://ocsaeon.itcnelita.com/api)
#    Keduanya tetap HANYA bisa diunduh dari LAN/Tailscale (berisi akun agent).
set -uo pipefail
sec() { echo; echo "##### $* #####"; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$REPO_DIR/agent/Install-OCS-Agent-AEON.bat.template"
F=/usr/share/ocsinventory-frontend
PRIV="$F/aeon/private"
DOMAIN=ocsaeon.itcnelita.com
PUB_API="https://${DOMAIN}/api"
LAN_API="http://192.168.100.122:8081"
. /root/ocsaeon-secrets/ocs3-agent.env

sec "1) ALUR AGENT LEWAT DOMAIN PUBLIK"
fail=0
for UA in "Dart/3.5 (dart:io)" ""; do
  echo "-- User-Agent: '${UA:-(kosong)}'"
  hdr=(-A "$UA")
  r=$(curl -s -m 20 -o /tmp/ocsaeon-r.txt -w '%{http_code}' "${hdr[@]}" "$PUB_API/api-check/")
  printf '   %-30s -> %s %s\n' "GET /api-check/" "$r" "$(head -c 80 /tmp/ocsaeon-r.txt | tr -d '\n')"
  [ "$r" = 200 ] || fail=1
  TOKEN=$(curl -s -m 20 "${hdr[@]}" -X POST -H 'Content-Type: application/json' \
    -d "{\"username\":\"$OCS_AGENT_USER\",\"password\":\"$OCS_AGENT_PWD\"}" "$PUB_API/api-auth/token" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))' 2>/dev/null)
  if [ -n "$TOKEN" ]; then echo "   POST /api-auth/token         -> token OK"; else echo "   POST /api-auth/token         -> GAGAL"; fail=1; fi
  for p in /myaccount/ /asset/configs/; do
    printf '   %-30s -> %s\n' "GET $p" "$(curl -s -m 20 -o /dev/null -w '%{http_code}' "${hdr[@]}" -H "Authorization: Token $TOKEN" "$PUB_API$p")"
  done
  curl -s -m 20 -o /dev/null "${hdr[@]}" -X POST -H "Authorization: Token $TOKEN" "$PUB_API/api-auth/token/logout"
done
rm -f /tmp/ocsaeon-r.txt
echo "-- installer exe lewat domain: $(curl -s -m 30 -o /dev/null -w '%{http_code} %{size_download}B' "https://${DOMAIN}/aeon/agent/$(basename "$(ls "$F"/aeon/agent/*.exe | sort -V | tail -1)")")"

sec "2) GENERATE .BAT (LAN & INTERNET)"
SETUP=$(ls "$F"/aeon/agent/OCSInventory-Agent-Setup-Windows-*.exe | sort -V | tail -1)
SETUP_NAME=$(basename "$SETUP"); SETUP_SHA=$(sha256sum "$SETUP" | cut -d' ' -f1)
gen() { # out url setup_base varian hint
  sed -e "s|__OCS_URL__|$2|g" -e "s|__SETUP_BASE__|$3|g" -e "s|__VARIAN__|$4|g" -e "s|__NET_HINT__|$5|g" \
      -e "s|__AGENT_USER__|${OCS_AGENT_USER}|g" -e "s|__AGENT_PASSWORD__|${OCS_AGENT_PWD}|g" \
      -e "s|__SETUP_NAME__|${SETUP_NAME}|g" -e "s|__SETUP_SHA256__|${SETUP_SHA}|g" \
      -e 's/\r*$/\r/' "$TPL" > "$PRIV/$1"
  chown root:www-data "$PRIV/$1"; chmod 640 "$PRIV/$1"
  cp "$PRIV/$1" "/root/ocsaeon-secrets/$1"; chmod 600 "/root/ocsaeon-secrets/$1"
  if grep -q '__[A-Z_]*__' "$PRIV/$1"; then echo "!! $1: placeholder belum terisi"; fail=1; else echo "$1: OK"; fi
  sed -e "s|${OCS_AGENT_PWD}|********|g" "$PRIV/$1" | sed -n '9,14p' | tr -d '\r' | sed 's/^/     /'
}
gen Install-OCS-Agent-AEON.bat          "$LAN_API" "http://192.168.100.122" "LAN kantor" "Pastikan PC terhubung ke LAN kantor."
gen Install-OCS-Agent-AEON-Internet.bat "$PUB_API" "https://${DOMAIN}"      "Internet"   "Pastikan PC terhubung ke internet."

sec "3) AKSES FILE .BAT"
for n in Install-OCS-Agent-AEON.bat Install-OCS-Agent-AEON-Internet.bat; do
  l=$(curl -s -o /dev/null -w '%{http_code}' "http://192.168.100.122/aeon/private/$n")
  p=$(curl -s -m 15 -o /dev/null -w '%{http_code}' "https://${DOMAIN}/aeon/private/$n")
  printf '%-38s LAN=%s (harap 200)  publik=%s (harap 403)\n' "$n" "$l" "$p"
  [ "$l" = 200 ] || fail=1
  if [ "$p" = 200 ]; then echo "!! $n bisa diakses publik -> dihapus"; rm -f "$PRIV/$n"; fail=1; fi
done
exit "$fail"
