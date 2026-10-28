#!/bin/bash
# 0020-diagnose-dashboard-error.sh — DIAGNOSA SAJA.
# Setelah login: "Oops, something went wrong" + "No dashboard configured".
set -uo pipefail
sec() { echo; echo "##### $* #####"; }
B=/usr/share/ocsinventory-backend
VENV=/usr/lib/ocsinventory-backend/venv
. /root/ocsaeon-secrets/ocs3-db.env
mask() { sed -e "s|${OCS3_DB_PWD}|****|g" -E -e 's/(Authorization: *Token )[A-Za-z0-9]+/\1****/g' -e 's/("token": *")[^"]+/\1****/g'; }

sec "REQUEST API YANG GAGAL (uWSGI, status >= 400, 60 terakhir)"
grep -E 'HTTP/1\.[01] (4|5)[0-9]{2}' /var/log/uwsgi/app/ocsinventory-backend.log | tail -n 60 | mask

sec "SEMUA REQUEST API 40 TERAKHIR"
grep -E '=> generated' /var/log/uwsgi/app/ocsinventory-backend.log | tail -n 40 | sed -E 's/\{[0-9]+ vars in [0-9]+ bytes\} //' | mask

sec "ERROR / TRACEBACK DI LOG BACKEND"
for f in "$B"/logs/ocs_backend.log "$B"/logs/ocs_django.log "$B"/logs/ocs_auth.log; do
  echo "======== $f"
  grep -n -E '\[(ERROR|CRITICAL)\]|Traceback|Exception' "$f" | tail -n 25 | mask
done
echo "======== uWSGI traceback terakhir"
grep -n -B2 -A25 'Traceback' /var/log/uwsgi/app/ocsinventory-backend.log | tail -n 60 | mask

sec "NGINX ERROR"
tail -n 20 /var/log/nginx/error.log
tail -n 20 /var/log/ocsinventory-frontend/error.log 2>/dev/null

sec "DATA DASHBOARD DI DB"
mariadb -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" -e "SHOW TABLES LIKE 'dashboard%';"
for t in $(mariadb -N -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" -e "SHOW TABLES LIKE 'dashboard%';"); do
  echo "-- $t: $(mariadb -N -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" -e "SELECT COUNT(*) FROM \`$t\`")"
done
echo "-- template/section/field (data inventaris dasar):"
for t in template_template section_section field_field config_config; do
  printf '%-22s %s\n' "$t" "$(mariadb -N -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" -e "SELECT COUNT(*) FROM \`$t\`" 2>&1)"
done

sec "PERINTAH manage.py demo (isi source, belum dijalankan)"
cat "$B/mgmt/management/commands/demo.py" | head -n 120
echo
echo "-- file data/fixture yang dipakai:"
find "$B" -path '*fixtures*' -name '*.json' | sed "s|$B/||" | head -20
grep -rln -i "dashboard" "$B"/*/migrations/*.py 2>/dev/null | sed "s|$B/||" | head -10

sec "MIGRASI BELUM DITERAPKAN?"
cd "$B" && sudo -u www-data "$VENV/bin/python3" manage.py showmigrations --plan 2>/dev/null | grep -c '\[ \]' | xargs echo "migrasi belum diterapkan:"

echo
echo "DIAGNOSA SELESAI"
