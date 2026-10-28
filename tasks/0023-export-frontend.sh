#!/bin/bash
# 0023-export-frontend.sh — SALIN SAJA, tidak mengubah server.
# Salin file statis frontend OCS 3 (paket publik) ke logs/ocs3-frontend/ supaya
# bisa dianalisis untuk branding AEON. config/ tidak ikut.
set -euo pipefail

SRC=/usr/share/ocsinventory-frontend
DEST="$(cd "$(dirname "$0")/.." && pwd)/logs/ocs3-frontend"

rm -rf "$DEST"; mkdir -p "$DEST"
cp -r "$SRC/assets" "$SRC/index.html" "$SRC/favicon.ico" "$DEST/"
[ -d "$SRC/extensions" ] && cp -r "$SRC/extensions" "$DEST/" || true
du -sh "$DEST"
find "$DEST" -type f | wc -l | xargs echo "jumlah file:"
echo "-- gambar:"
find "$DEST" -type f \( -name '*.png' -o -name '*.svg' -o -name '*.jpg' -o -name '*.webp' -o -name '*.ico' \) -printf '%s\t%P\n' | sort -k2
echo "-- css:"
find "$DEST" -type f -name '*.css' -printf '%s\t%P\n' | sort -k2 | head -20
