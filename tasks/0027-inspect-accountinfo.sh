#!/bin/bash
# 0027-inspect-accountinfo.sh   (READ-ONLY, tidak mengubah apa pun)
# Tujuan: siapkan fitur Asset ID + barcode + stocktake.
# - Daftar tabel DB ocsv3 + jumlah baris
# - Struktur tabel yang terkait accountinfo / asset / hardware / device
# - Source accountinfo backend (models, serializers, views, routers)
# - Cek route API accountinfo di backend lokal
# Tidak ada password / secret yang dicetak.
set -uo pipefail

SECRETS=/root/ocsaeon-secrets
BACKEND_DIR=/usr/share/ocsinventory-backend
. "$SECRETS/ocs3-db.env"

q() { mariadb -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" "$@" 2>&1 | grep -v -F "$OCS3_DB_PWD"; }
sec() { echo; echo "##### $* #####"; }

sec "TABEL + PERKIRAAN JUMLAH BARIS"
q -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='${OCS3_DB_NAME}' ORDER BY table_name"

sec "STRUKTUR TABEL TERKAIT (accountinfo|asset|hardware|device|computer)"
for t in $(q -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='${OCS3_DB_NAME}' AND table_name REGEXP 'accountinfo|asset|hardware|device|computer' ORDER BY table_name"); do
  echo "--- $t"
  q -e "SHOW COLUMNS FROM \`$t\`"
done

sec "ISI accountinfo config (nama field saja, tanpa data asset)"
for t in $(q -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='${OCS3_DB_NAME}' AND table_name REGEXP 'accountinfo.*config'"); do
  echo "--- $t"
  q -e "SELECT * FROM \`$t\` LIMIT 20"
done

sec "SOURCE BACKEND accountinfo"
for f in models.py serializers.py views.py routers.py urls.py permissions.py; do
  p="$BACKEND_DIR/accountinfo/$f"
  if [ -f "$p" ]; then echo; echo "======== accountinfo/$f"; sed -n '1,200p' "$p"; fi
done

sec "SOURCE BACKEND asset (models + serializers, 200 baris pertama)"
for f in models.py serializers.py; do
  p="$BACKEND_DIR/asset/$f"
  if [ -f "$p" ]; then echo; echo "======== asset/$f"; sed -n '1,200p' "$p"; fi
done
echo; echo "-- app backend:"; ls "$BACKEND_DIR"

sec "ROUTE API (tanpa login: 401 = route ada)"
for u in /accountinfo/config/ /accountinfo/value/ /asset/ /asset/computer/ /api-check/; do
  printf '%-28s -> %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8081$u")"
done

echo
echo "INSPEKSI SELESAI (tidak ada perubahan di server)"
exit 0
