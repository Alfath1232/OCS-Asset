#!/bin/bash
# 0035-inspect-asset-model.sh   (READ-ONLY)
# Lanjutan 0027-inspect-accountinfo: bahan desain Asset ID + barcode + stocktake.
# - Source model aset utama (asset/inventory_base) + cara agent mengenali aset (collection)
# - Struktur & isi ringkas tabel inventory_base_inventorybase
# - Uji API accountinfo & asset/bases dengan token admin SEMENTARA (dibuat & dihapus di sini,
#   tanpa password admin). Tidak ada data yang diubah.
set -uo pipefail
sec() { echo; echo "##### $* #####"; }
B=/usr/share/ocsinventory-backend
VENV=/usr/lib/ocsinventory-backend/venv
. /root/ocsaeon-secrets/ocs3-db.env
q() { mariadb -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" "$@" 2>&1 | grep -v -F "$OCS3_DB_PWD"; }
dj() { (cd "$B" && sudo -u www-data "$VENV/bin/python3" manage.py shell -c "$1" 2>&1 | grep -v 'objects imported'); }

sec "STRUKTUR APP asset/"
find "$B/asset" -maxdepth 2 -name '*.py' ! -path '*migrations*' ! -name '__init__.py' | sed "s|$B/||" | sort

sec "SOURCE asset/inventory_base (models, serializers, routers, filter di views)"
for f in models.py serializers.py routers.py; do
  p="$B/asset/inventory_base/$f"; [ -f "$p" ] && { echo "======== asset/inventory_base/$f"; sed -n '1,220p' "$p"; }
done
echo "======== asset/inventory_base/views.py (filter & search)"
grep -n -E "class |filterset|search_fields|ordering|def get_queryset" "$B/asset/inventory_base/views.py" 2>/dev/null | head -30

sec "CARA AGENT MENGENALI ASET (asset/collection, kunci identitas)"
grep -n -i -E "uuid|hostname|serial|unique|get_or_create|filter\(|reconcil" "$B"/asset/collection/*.py "$B"/asset/reconciliation/*.py 2>/dev/null | head -40

sec "TABEL inventory_base_inventorybase"
q -e "SHOW COLUMNS FROM inventory_base_inventorybase"
q -e "SELECT COUNT(*) AS jumlah_aset FROM inventory_base_inventorybase"
echo "-- isi ringkas (kolom teks dipotong 60 karakter):"
cols=$(q -N -e "SELECT GROUP_CONCAT(CASE WHEN data_type IN ('longtext','text','json') THEN CONCAT('LEFT(\`',column_name,'\`,60) AS \`',column_name,'\`') ELSE CONCAT('\`',column_name,'\`') END ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='${OCS3_DB_NAME}' AND table_name='inventory_base_inventorybase'")
q -e "SELECT ${cols} FROM inventory_base_inventorybase LIMIT 5\G"

sec "ACCOUNTINFO SAAT INI"
q -e "SELECT COUNT(*) AS config FROM accountinfo_accountinfoconfig; SELECT COUNT(*) AS data FROM accountinfo_accountinfodata; SELECT id, object_slug, object_id, LEFT(accountdata,120) AS accountdata FROM accountinfo_accountinfodata LIMIT 5;"

sec "UJI API DENGAN TOKEN ADMIN SEMENTARA"
TOKEN=$(dj "
from django.contrib.auth import get_user_model
from knox.models import AuthToken
u = get_user_model().objects.filter(is_superuser=True).order_by('id').first()
inst, tok = AuthToken.objects.create(u)
print('TOKEN=' + tok)
" | sed -n 's/^TOKEN=//p')
cleanup() {
  [ -n "${TOKEN:-}" ] && curl -s -o /dev/null -X POST -H "Authorization: Token $TOKEN" http://127.0.0.1:8081/api-auth/token/logout
}
trap cleanup EXIT
if [ -z "$TOKEN" ]; then echo "!! gagal membuat token sementara"; else echo "token sementara: OK (dihapus di akhir)"; fi
api() { curl -s -m 20 -H "Authorization: Token $TOKEN" "http://127.0.0.1:8081$1"; }
for p in /accountinfo/config/ /accountinfo/value/ /accountinfo/data/ "/asset/bases/?limit=2"; do
  echo "--- GET $p -> $(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Token $TOKEN" "http://127.0.0.1:8081$p")"
  api "$p" | python3 -c '
import sys, json
def short(v, n=0):
    if isinstance(v, dict):
        return {k: short(x, n+1) for k, x in list(v.items())[:25]}
    if isinstance(v, list):
        return [short(x, n+1) for x in v[:2]] + (["... %d item lagi" % (len(v)-2)] if len(v) > 2 else [])
    if isinstance(v, str) and len(v) > 80:
        return v[:80] + "..."
    return v
try:
    print(json.dumps(short(json.load(sys.stdin)), indent=1, ensure_ascii=False)[:3000])
except Exception as e:
    print("(bukan JSON)", e)'
done
echo "--- OPTIONS /accountinfo/config/ (field yang diterima saat membuat custom field)"
curl -s -X OPTIONS -H "Authorization: Token $TOKEN" http://127.0.0.1:8081/accountinfo/config/ \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get("actions",{}).get("POST",d), indent=1)[:2500])' 2>/dev/null

sec "UI FRONTEND UNTUK CUSTOM FIELD"
ls /usr/share/ocsinventory-frontend/assets | grep -i -E "accountinfo|asset"

echo
echo "INSPEKSI SELESAI (tidak ada perubahan data)"
exit 0
