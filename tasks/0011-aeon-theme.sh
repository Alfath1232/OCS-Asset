#!/bin/bash
# 0011-aeon-theme.sh
# Pasang tema web console AEON (logo, warna magenta AEON, halaman login, favicon).
# Aset ada di repo: branding/aeon-theme/
#
# Rollback (kembali ke tema bawaan OCS):
#   mariadb ocsweb -e "UPDATE config SET TVALUE='OCS' WHERE NAME='CUSTOM_THEME'"
#   cp /root/ocs-install/favicon.ico.orig /usr/share/ocsinventory-reports/ocsreports/favicon.ico
#   (atau via web: Configuration > General configuration > tema = OCS)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_DIR/branding/aeon-theme"
WEBROOT=/usr/share/ocsinventory-reports/ocsreports
DEST="$WEBROOT/themes/AEON"

echo "== Aset tema di repo:"
ls -l "$SRC"
for f in style.css banniere.png logo.png favicon.ico; do
  [ -s "$SRC/$f" ] || { echo "!! aset hilang: $f"; exit 1; }
done

echo "== Pasang folder tema $DEST"
install -d -m 755 "$DEST"
install -m 644 -o root -g www-data "$SRC/style.css"    "$DEST/style.css"
install -m 644 -o root -g www-data "$SRC/banniere.png" "$DEST/banniere.png"
install -m 644 -o root -g www-data "$SRC/logo.png"     "$DEST/logo.png"
ls -l "$DEST"

echo "== Favicon (backup asli sekali saja)"
if [ ! -f /root/ocs-install/favicon.ico.orig ]; then
  cp -v "$WEBROOT/favicon.ico" /root/ocs-install/favicon.ico.orig
fi
install -m 644 -o root -g www-data "$SRC/favicon.ico" "$WEBROOT/favicon.ico"

echo "== Aktifkan tema AEON di konfigurasi OCS"
mariadb ocsweb -e "INSERT INTO config (NAME, IVALUE, TVALUE, COMMENTS)
  VALUES ('CUSTOM_THEME', 0, 'AEON', 'Tema web console')
  ON DUPLICATE KEY UPDATE TVALUE='AEON';"
mariadb -N ocsweb -e "SELECT NAME, TVALUE FROM config WHERE NAME='CUSTOM_THEME'"

echo "== Verifikasi lewat HTTP"
fail=0
for p in themes/AEON/style.css themes/AEON/banniere.png themes/AEON/logo.png favicon.ico; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost/ocsreports/$p")
  printf '%-28s -> HTTP %s\n' "$p" "$code"
  [ "$code" = "200" ] || fail=1
done
page=$(curl -s "http://localhost/ocsreports/index.php")
if echo "$page" | grep -q 'themes/AEON/'; then
  echo "Halaman login memakai tema AEON: OK"
else
  echo "!! Halaman login belum memakai tema AEON"; fail=1
fi
cmp -s "$SRC/favicon.ico" "$WEBROOT/favicon.ico" && echo "Favicon AEON terpasang: OK" || fail=1

exit "$fail"
