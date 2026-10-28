#!/bin/bash
# 0037-aeon-apps.sh
# Pasang halaman AEON:
#   /aeon/labels/     cetak label QR/Code128 (A4 3x8 atau label 50x25 mm)
#   /aeon/stocktake/  stocktake lewat HP (scan label, catat Sesuai/Pindah/Tidak ditemukan)
# Login memakai akun OCS yang sama (token console). File statis saja, tanpa secret.
# Rollback: rm -rf /usr/share/ocsinventory-frontend/aeon/{labels,stocktake,shared,vendor}
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_DIR/aeon-apps"
DEST=/usr/share/ocsinventory-frontend/aeon
DOMAIN=ocsaeon.itcnelita.com
VER=$(git -C "$REPO_DIR" log -1 --format=%h -- aeon-apps 2>/dev/null || date +%s)

for d in labels stocktake shared vendor; do
  rm -rf "$DEST/$d"
  cp -r "$SRC/$d" "$DEST/$d"
done
find "$DEST"/labels "$DEST"/stocktake -name '*.html' -exec sed -i "s/__VER__/${VER}/g" {} +
chown -R www-data:www-data "$DEST"/labels "$DEST"/stocktake "$DEST"/shared "$DEST"/vendor
find "$DEST"/labels "$DEST"/stocktake "$DEST"/shared "$DEST"/vendor -type d -exec chmod 755 {} +
find "$DEST"/labels "$DEST"/stocktake "$DEST"/shared "$DEST"/vendor -type f -exec chmod 644 {} +
echo "versi: $VER"
grep -rl '__VER__' "$DEST"/labels "$DEST"/stocktake && { echo "!! __VER__ tersisa"; exit 1; } || echo "nomor versi terpasang"

fail=0
H=(-H "Host: ${DOMAIN}" -H "X-Forwarded-Proto: https")
check() { local c; c=$(curl -s -o /dev/null -w '%{http_code}' "$@"); echo "$c"; }
for p in /aeon/labels/ /aeon/stocktake/ "/aeon/labels/labels.js?v=$VER" "/aeon/stocktake/stocktake.js?v=$VER" \
         "/aeon/shared/ocs.js?v=$VER" "/aeon/shared/aeon-app.css?v=$VER" /aeon/shared/aeon-logo.svg \
         /aeon/shared/aeon-logo-black.svg /aeon/shared/PlusJakartaSans-var.woff2 \
         "/aeon/vendor/qrcode.js?v=$VER" "/aeon/vendor/JsBarcode.all.min.js?v=$VER" "/aeon/vendor/html5-qrcode.min.js?v=$VER"; do
  c=$(check "${H[@]}" "http://localhost$p"); printf '%-48s -> %s\n' "$p" "$c"; [ "$c" = 200 ] || fail=1
done
echo "-- halaman label benar-benar halaman label (bukan fallback console):"
curl -s "${H[@]}" http://localhost/aeon/labels/ | grep -o '<title>[^<]*</title>'
curl -s "${H[@]}" http://localhost/aeon/stocktake/ | grep -o '<title>[^<]*</title>'
echo "-- lewat domain publik:"
for p in /aeon/labels/ /aeon/stocktake/; do
  printf '%-48s -> %s\n' "https://${DOMAIN}$p" "$(curl -s -m 20 -o /dev/null -w '%{http_code}' "https://${DOMAIN}$p")"
done
exit "$fail"
