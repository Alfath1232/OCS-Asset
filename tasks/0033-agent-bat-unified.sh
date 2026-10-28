#!/bin/bash
# 0033-agent-bat-unified.sh
# Satukan installer agent: 1 file .bat yang otomatis memilih jalur
#   - agent  -> domain bila internet tersedia, kalau tidak -> LAN
#   - unduh installer -> LAN bila terjangkau, kalau tidak -> domain
# Nama file lama (...-Internet.bat) diisi konten yang sama supaya link lama tetap jalan.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$REPO_DIR/agent/Install-OCS-Agent-AEON.bat.template"
F=/usr/share/ocsinventory-frontend
PRIV="$F/aeon/private"
DOMAIN=ocsaeon.itcnelita.com
. /root/ocsaeon-secrets/ocs3-agent.env

SETUP=$(ls "$F"/aeon/agent/OCSInventory-Agent-Setup-Windows-*.exe | sort -V | tail -1)
SETUP_NAME=$(basename "$SETUP"); SETUP_SHA=$(sha256sum "$SETUP" | cut -d' ' -f1)

OUT="$PRIV/Install-OCS-Agent-AEON.bat"
sed -e "s|__URL_NET__|https://${DOMAIN}/api|g" \
    -e "s|__URL_LAN__|http://192.168.100.122:8081|g" \
    -e "s|__DL_NET__|https://${DOMAIN}|g" \
    -e "s|__DL_LAN__|http://192.168.100.122|g" \
    -e "s|__AGENT_USER__|${OCS_AGENT_USER}|g" \
    -e "s|__AGENT_PASSWORD__|${OCS_AGENT_PWD}|g" \
    -e "s|__SETUP_NAME__|${SETUP_NAME}|g" \
    -e "s|__SETUP_SHA256__|${SETUP_SHA}|g" \
    -e 's/\r*$/\r/' "$TPL" > "$OUT"
cp "$OUT" "$PRIV/Install-OCS-Agent-AEON-Internet.bat"
for f in "$OUT" "$PRIV/Install-OCS-Agent-AEON-Internet.bat"; do chown root:www-data "$f"; chmod 640 "$f"; done
cp "$OUT" /root/ocsaeon-secrets/Install-OCS-Agent-AEON.bat; chmod 600 /root/ocsaeon-secrets/Install-OCS-Agent-AEON.bat
rm -f /root/ocsaeon-secrets/Install-OCS-Agent-AEON-Internet.bat

fail=0
if grep -q '__[A-Z0-9_]*__' "$OUT"; then echo "!! placeholder belum terisi"; fail=1; else echo "placeholder: semua terisi"; fi
printf 'baris: %s, CRLF: %s\n' "$(wc -l < "$OUT")" "$(grep -c $'\r$' "$OUT")"
echo "-- konfigurasi (password disamarkan):"
sed -e "s|${OCS_AGENT_PWD}|********|g" "$OUT" | sed -n '9,16p' | tr -d '\r' | sed 's/^/   /'

echo "-- jalur yang akan dicek .bat (dari server):"
printf '   %-44s -> %s\n' "https://${DOMAIN}/api/api-check/" "$(curl -s -m 15 -o /dev/null -w '%{http_code}' "https://${DOMAIN}/api/api-check/")"
printf '   %-44s -> %s\n' "http://192.168.100.122:8081/api-check/" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://192.168.100.122:8081/api-check/)"

echo "-- akses file:"
for n in Install-OCS-Agent-AEON.bat Install-OCS-Agent-AEON-Internet.bat; do
  l=$(curl -s -o /dev/null -w '%{http_code}' "http://192.168.100.122/aeon/private/$n")
  p=$(curl -s -m 15 -o /dev/null -w '%{http_code}' "https://${DOMAIN}/aeon/private/$n")
  printf '   %-38s LAN=%s (harap 200)  domain tanpa password=%s (harap 401)\n' "$n" "$l" "$p"
  [ "$l" = 200 ] && [ "$p" = 401 ] || fail=1
done
exit "$fail"
