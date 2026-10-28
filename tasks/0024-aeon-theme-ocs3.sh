#!/bin/bash
# 0024-aeon-theme-ocs3.sh
# Tema AEON untuk frontend OCS 3 (Vue + Tabler):
#   - aeon.css dimuat setelah CSS bawaan (warna magenta AEON, header, login, dropdown, tabel)
#   - logo header (logo-white-*.png) -> logo AEON putih + "IT Asset Inventory"
#   - gambar login (illu_communaute-*.png) -> logo AEON + "IT Asset Management"
#   - favicon AEON, judul tab "AEON IT Asset Inventory"
# Aset: branding/aeon-ocs3/ di repo. File asli di-backup sekali ke /root/ocs-install/ocs3-frontend-orig/
# Catatan: upgrade paket ocsinventory-frontend akan menimpa perubahan ini -> jalankan ulang task ini.
#
# Rollback:
#   cp -a /root/ocs-install/ocs3-frontend-orig/. /usr/share/ocsinventory-frontend/
#   rm -rf /usr/share/ocsinventory-frontend/aeon
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_DIR/branding/aeon-ocs3"
F=/usr/share/ocsinventory-frontend
BK=/root/ocs-install/ocs3-frontend-orig
VER=$(git -C "$REPO_DIR" log -1 --format=%h -- branding/aeon-ocs3 2>/dev/null || date +%s)

for f in aeon.css header-logo.png login-logo.png favicon.ico; do
  [ -s "$SRC/$f" ] || { echo "!! aset hilang: $f"; exit 1; }
done

LOGO=$(ls "$F"/assets/logo-white-*.png | head -1)
ILLU=$(ls "$F"/assets/illu_communaute-*.png | head -1)
echo "logo header : $LOGO"
echo "gambar login: $ILLU"

echo "== Backup file asli (sekali saja)"
if [ ! -d "$BK" ]; then
  install -d -m 700 "$BK/assets"
  cp -av "$F/index.html" "$F/favicon.ico" "$BK/"
  cp -av "$LOGO" "$ILLU" "$BK/assets/"
else
  echo "backup sudah ada: $BK"
fi

echo "== Pasang aset AEON"
install -d -m 755 -o www-data -g www-data "$F/aeon"
install -m 644 -o www-data -g www-data "$SRC/aeon.css"       "$F/aeon/aeon.css"
install -m 644 -o www-data -g www-data "$SRC/header-logo.png" "$LOGO"
install -m 644 -o www-data -g www-data "$SRC/login-logo.png"  "$ILLU"
install -m 644 -o www-data -g www-data "$SRC/favicon.ico"     "$F/favicon.ico"

echo "== index.html: judul + link aeon.css (idempotent)"
python3 - "$F/index.html" "$VER" <<'PY'
import re, sys
p, ver = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r"<title>.*?</title>", "<title>AEON IT Asset Inventory</title>", s, flags=re.S)
s = re.sub(r'\s*<link rel="stylesheet" href="/aeon/aeon\.css[^"]*">', "", s)
s = s.replace("</head>", f'  <link rel="stylesheet" href="/aeon/aeon.css?v={ver}">\n  </head>', 1)
open(p, "w").write(s)
PY
chown www-data:www-data "$F/index.html"
cat "$F/index.html"

echo "== Verifikasi"
fail=0
H=(-H "Host: ocsaeon.itcnelita.com" -H "X-Forwarded-Proto: https")
curl -s "${H[@]}" http://localhost/ | grep -q '/aeon/aeon.css' && echo "index memuat aeon.css: OK" || fail=1
for p in /aeon/aeon.css "${LOGO#$F}" "${ILLU#$F}" /favicon.ico; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "http://localhost$p")
  printf '%-48s -> %s\n' "$p" "$code"; [ "$code" = "200" ] || fail=1
done
cmp -s "$SRC/header-logo.png" "$LOGO" && echo "logo header AEON: OK" || fail=1
cmp -s "$SRC/login-logo.png"  "$ILLU" && echo "gambar login AEON: OK" || fail=1
exit "$fail"
