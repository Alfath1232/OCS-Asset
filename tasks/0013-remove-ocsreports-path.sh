#!/bin/bash
# 0013-remove-ocsreports-path.sh
# Hilangkan path /ocsreports sepenuhnya (404). Console hanya di http://<server>/
# - Nonaktifkan "Alias /ocsreports" di ocsinventory-reports.conf (alias /download & /snmp tetap)
# - Hapus RedirectMatch /ocsreports di site ocsaeon.conf
# Catatan: kalau setup.sh OCS dijalankan ulang (upgrade), alias ini akan muncul lagi.
#
# Rollback:
#   cp /root/ocs-install/ocsinventory-reports.conf.bak-0013 /etc/apache2/conf-available/ocsinventory-reports.conf
#   cp /root/ocs-install/ocsaeon.conf.bak-0013 /etc/apache2/sites-available/ocsaeon.conf
#   systemctl reload apache2
set -euo pipefail

CONF=/etc/apache2/conf-available/ocsinventory-reports.conf
SITE=/etc/apache2/sites-available/ocsaeon.conf

echo "== Backup config"
cp -v "$CONF" /root/ocs-install/ocsinventory-reports.conf.bak-0013
cp -v "$SITE" /root/ocs-install/ocsaeon.conf.bak-0013

echo "== Baris Alias sebelum:"
grep -n '^\s*#\?\s*Alias' "$CONF"

echo "== Nonaktifkan Alias /ocsreports"
sed -i -E 's|^(\s*)(Alias\s+/ocsreports\s+.*)$|\1# [ocsaeon 0013] \2|' "$CONF"
grep -n '^\s*#\?\s*\(# \[ocsaeon 0013\] \)\?Alias' "$CONF"

echo "== Hapus redirect /ocsreports dari site"
sed -i -E '/URL lama \/ocsreports/d; /RedirectMatch 301 \^\/ocsreports/d' "$SITE"
grep -n 'ocsreports' "$SITE" || echo "(tidak ada lagi referensi /ocsreports di site)"

if ! apache2ctl configtest; then
  echo "!! configtest gagal, rollback"
  cp /root/ocs-install/ocsinventory-reports.conf.bak-0013 "$CONF"
  cp /root/ocs-install/ocsaeon.conf.bak-0013 "$SITE"
  exit 1
fi
systemctl reload apache2
sleep 2

echo "== Verifikasi"
fail=0
check() {
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost$1")
  printf '%-28s -> HTTP %s (harap %s)\n' "$1" "$code" "$2"
  [ "$code" = "$2" ] || fail=1
}
check /                         200
check /themes/AEON/style.css    200
check /ocsreports               404
check /ocsreports/              404
check /ocsreports/index.php     404
check /ocsinventory             400
# /download harus tetap ter-alias (403/404 untuk folder kosong boleh, asal bukan 5xx)
dl=$(curl -s -o /dev/null -w '%{http_code}' http://localhost/download/)
printf '%-28s -> HTTP %s (harap bukan 5xx)\n' "/download/" "$dl"
case "$dl" in 5*) fail=1 ;; esac
curl -s http://localhost/ | grep -q 'themes/AEON/' && echo "Root = console OCS tema AEON: OK" || fail=1

exit "$fail"
