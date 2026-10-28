#!/bin/bash
# 0016-disk-and-ocs3-source.sh
# 1) Perbesar root LV 15G -> pakai semua sisa VG (online, tanpa downtime)
# 2) Baca source backend OCS 3 dari paket yang sudah di-download di 0015 (belum dipasang)
set -uo pipefail
sec() { echo; echo "##### $* #####"; }

sec "PERBESAR DISK ROOT"
df -h /
vgs
free_ext=$(vgs --noheadings -o vg_free_count ubuntu-vg | tr -d ' ')
if [ "${free_ext:-0}" -gt 0 ]; then
  lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
else
  echo "VG tidak punya ruang kosong lagi"
fi
df -h /

B=/root/ocs3-inspect/x/ocsinventory-backend/usr/share/ocsinventory-backend
show() { echo; echo "======== $1"; if [ -f "$1" ]; then cat "$1"; else echo "(tidak ada)"; fi; }

sec "REQUIREMENTS"
show "$B/requirements.txt"
show "$B/requirements_mysql.txt"
show "$B/requirements_psql.txt"

sec "SETTINGS.PY (baris penting)"
grep -n -E "environ|getenv|config\(|ALLOWED_HOSTS|CORS|CSRF|FRONTEND|SECRET_KEY|FIELD_ENCRYPTION|DATABASES|ENGINE|STATIC|LOGGING|TIME_ZONE|AUTH_USER_MODEL|REST_FRAMEWORK|INSTALLED_APPS" "$B/ocsinventory_backend/settings.py" | head -80

sec "URLS (endpoint)"
show "$B/ocsinventory_backend/urls.py"
grep -rn -E "path\(|re_path\(" "$B/inventory/urls.py" 2>/dev/null | head -30

sec "PERINTAH manage.py KUSTOM"
find "$B" -path '*management/commands/*.py' ! -name '__init__.py' | sed "s|$B/||"
for f in $(find "$B" -path '*management/commands/encryption_key.py'); do show "$f"; done

sec "AKUN ADMIN PERTAMA (cari di source)"
grep -rn -i -E "create_superuser|createsuperuser|default.*admin|username=.admin|'admin'|\"admin\"" "$B" --include=*.py \
  | grep -v -E '/tests?/|test_' | head -30
echo "-- README:"
grep -n -i -E "admin|superuser|login|password|createsuper" "$B/README.md" | head -30

echo
echo "SELESAI (disk diperbesar; OCS 3 belum dipasang)"
