#!/bin/bash
# 0019-fix-venv-permissions.sh
# Perbaikan 0017: umask 077 terbawa ke pip install mysqlclient -> modul MySQLdb
# tidak bisa dibaca www-data (uWSGI) -> backend HTTP 500.
# Buka izin baca kode (venv, backend, frontend). Secret (.env, /root/ocsaeon-secrets) tetap tertutup.
set -euo pipefail

VENV=/usr/lib/ocsinventory-backend/venv
B=/usr/share/ocsinventory-backend
F=/usr/share/ocsinventory-frontend

echo "== Sebelum: file venv yang tidak bisa dibaca 'other'"
find "$VENV" ! -perm -o=r | head -10
echo "jumlah: $(find "$VENV" ! -perm -o=r | wc -l)"

echo "== Perbaiki izin baca (a+rX = baca semua, eksekusi hanya folder/yang sudah executable)"
chmod -R a+rX "$VENV"
find "$B" -path "$B/.env" -prune -o -path "$B/logs" -prune -o -exec chmod a+rX {} +
chmod -R a+rX "$F"
chmod 640 "$B/.env"; chown www-data:www-data "$B/.env"
echo "sisa file venv tidak terbaca: $(find "$VENV" ! -perm -o=r | wc -l)"

echo "== Tes import driver sebagai www-data"
sudo -u www-data "$VENV/bin/python3" -c "import MySQLdb.constants, MySQLdb; print('MySQLdb OK', MySQLdb.version_info)"
cd "$B" && sudo -u www-data "$VENV/bin/python3" manage.py check 2>&1 | tail -n 3

echo "== Restart uWSGI"
systemctl restart uwsgi
sleep 4
grep -E "WSGI app 0 .* ready|unable to load app|no python application" /var/log/uwsgi/app/ocsinventory-backend.log | tail -n 3 || true

echo "== Verifikasi HTTP"
fail=0
c() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
r1=$(c http://localhost:8081/); r2=$(c http://localhost:8081/api-check/); r3=$(c http://localhost/)
printf '%-34s -> %s (harap 401)\n' "backend /"           "$r1"
printf '%-34s -> %s\n'            "backend /api-check/"  "$r2"
printf '%-34s -> %s (harap 200)\n' "frontend /"          "$r3"
[ "$r1" = "401" ] || [ "$r1" = "200" ] || fail=1
[ "$r3" = "200" ] || fail=1
echo "-- isi /api-check/:"; curl -s http://localhost:8081/api-check/ | head -c 300; echo
echo "-- tes login admin/admin ke /login/ (status saja):"
printf '%s\n' "$(c -X POST -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}' http://localhost:8081/login/)"
echo "-- tes login ke /api-auth/token (status saja):"
printf '%s\n' "$(c -X POST -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}' http://localhost:8081/api-auth/token)"

exit "$fail"
