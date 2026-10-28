#!/bin/bash
# 0017-install-ocs3.sh   (DISRUPTIF: OCS 2.12.6 + Apache dimatikan, diganti OCS 3.0)
#
# - Matikan & disable Apache (paket OCS 2 TIDAK dihapus -> bisa rollback)
# - DB baru di MariaDB: ocsv3 / user ocsv3 (password acak, simpan di /root/ocsaeon-secrets)
# - Pasang paket ocsinventory-server 3.0.0-1 (backend Django+uWSGI, frontend Vue, nginx)
# - Isi .env: FIELD_ENCRYPTION_KEY (Fernet), FRONTEND_REDIRECT
# - Jalankan configure script resmi secara non-interaktif (MySQL/MariaDB) -> migrasi DB
# - Frontend config.json -> API di http://100.105.251.78:8081/
#
# Akses setelah selesai:
#   Web console : http://100.105.251.78/          (login default admin / admin)
#   Backend API : http://100.105.251.78:8081/      (401 di root = normal)
#   Agent v3    : http://192.168.100.122:8081/asset/collection/
#   Agent 2.x   : http://192.168.100.122:8081/asset/legacy/
#
# Rollback ke OCS 2.12.6:
#   systemctl disable --now nginx uwsgi
#   systemctl enable --now apache2
set -euo pipefail

PUBLIC_HOST=100.105.251.78
BACKEND_DIR=/usr/share/ocsinventory-backend
FRONTEND_DIR=/usr/share/ocsinventory-frontend
VENV=/usr/lib/ocsinventory-backend/venv
SECRETS=/root/ocsaeon-secrets
DB_ENV=$SECRETS/ocs3-db.env
KEY_FILE=$SECRETS/ocs3-field-encryption-key

echo "== [1] Matikan Apache / OCS 2.12.6 (paket tetap ada untuk rollback)"
systemctl disable --now apache2
sleep 1
if ss -tlnp | grep -qE ':80\b'; then echo "!! port 80 masih dipakai:"; ss -tlnp | grep -E ':80\b'; exit 1; fi
echo "port 80 bebas"

echo "== [2] Dependensi build driver MariaDB (mysqlclient)"
apt-get install -y -q default-libmysqlclient-dev pkg-config >/dev/null
pkg-config --exists mysqlclient && echo "mysqlclient dev: OK"

echo "== [3] Database ocsv3"
install -d -m 700 "$SECRETS"
if [ ! -f "$DB_ENV" ]; then
  ( umask 077; printf 'OCS3_DB_NAME=ocsv3\nOCS3_DB_USER=ocsv3\nOCS3_DB_PWD=%s\n' "$(openssl rand -hex 16)" > "$DB_ENV" )
fi
chmod 600 "$DB_ENV"
. "$DB_ENV"
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS ${OCS3_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${OCS3_DB_USER}'@'localhost' IDENTIFIED BY '${OCS3_DB_PWD}';
ALTER USER '${OCS3_DB_USER}'@'localhost' IDENTIFIED BY '${OCS3_DB_PWD}';
GRANT ALL PRIVILEGES ON ${OCS3_DB_NAME}.* TO '${OCS3_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
mariadb -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" -e "SELECT CURRENT_USER() AS login_ok" "$OCS3_DB_NAME"

echo "== [4] Pasang paket OCS 3.0.0-1 (pip install di postinst, bisa beberapa menit)"
set +e
apt-get install -y -q ocsinventory-server=3.0.0-1 > /root/ocs3-apt-install.log 2>&1
rc=$?
set -e
grep -v -E '^(Get:|Selecting|Preparing|Unpacking|Setting up|Processing triggers|\(Reading)' /root/ocs3-apt-install.log | tail -n 40 || true
if [ "$rc" -ne 0 ]; then echo "!! apt install exit $rc"; exit "$rc"; fi
dpkg -l ocsinventory-server ocsinventory-backend ocsinventory-frontend | awk '/^ii/{print $2, $3}'

echo "== [5] .env: encryption key + frontend redirect"
if [ ! -f "$KEY_FILE" ]; then
  ( umask 077; "$VENV/bin/python3" -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" > "$KEY_FILE" )
fi
chmod 600 "$KEY_FILE"
FKEY=$(cat "$KEY_FILE")
sed -i "s|^FIELD_ENCRYPTION_KEY=.*|FIELD_ENCRYPTION_KEY='${FKEY}'|" "$BACKEND_DIR/.env"
sed -i "s|^FRONTEND_REDIRECT=.*|FRONTEND_REDIRECT='http://${PUBLIC_HOST}'|" "$BACKEND_DIR/.env"
grep -q 'a-not-secure-key' "$BACKEND_DIR/.env" && { echo "!! SECRET_KEY masih default"; exit 1; } || echo "SECRET_KEY: sudah di-generate postinst"

echo "== [6] Configure script resmi (non-interaktif: MariaDB @ localhost:3306)"
set +e
printf '2\nlocalhost\n3306\n%s\n%s\n%s\n' "$OCS3_DB_NAME" "$OCS3_DB_USER" "$OCS3_DB_PWD" \
  | bash "$BACKEND_DIR/tools/configure-ocsinventory-backend.sh" 2>&1 | grep -v -F "$OCS3_DB_PWD" | tail -n 40
rc=${PIPESTATUS[1]}
set -e
if [ "$rc" -ne 0 ]; then
  echo "!! configure script exit $rc. 40 baris terakhir log migrasi:"
  tail -n 40 /tmp/ocsinventory-backend-configuration.log | grep -v -F "$OCS3_DB_PWD" || true
  exit "$rc"
fi
echo "-- .env (rahasia disamarkan):"
sed -E "s/^(SECRET_KEY|DB_PASSWORD|FIELD_ENCRYPTION_KEY)=.*/\1=********/" "$BACKEND_DIR/.env"

echo "== [7] collectstatic (untuk halaman API/admin Django)"
( cd "$BACKEND_DIR" && "$VENV/bin/python3" manage.py collectstatic --noinput 2>&1 | tail -n 2 )
chown -R www-data:www-data "$BACKEND_DIR"
chmod 640 "$BACKEND_DIR/.env"

echo "== [8] Frontend -> alamat API"
cat > "$FRONTEND_DIR/config/config.json" <<JSON
{
  "BACKEND_API_ROUTE": "http://${PUBLIC_HOST}:8081/"
}
JSON
chown www-data: "$FRONTEND_DIR/config/config.json"
cat "$FRONTEND_DIR/config/config.json"

echo "== [9] Service"
systemctl enable nginx uwsgi >/dev/null 2>&1
systemctl restart uwsgi nginx
sleep 4
for u in nginx uwsgi mariadb; do printf '%-8s %s / %s\n' "$u" "$(systemctl is-active $u)" "$(systemctl is-enabled $u)"; done
ss -tlnp | grep -E ':(80|8081)\b' || echo "!! nginx belum listen di 80/8081"

echo "== [10] Verifikasi"
fail=0
c() { curl -s -o /dev/null -w '%{http_code}' "$1"; }
printf '%-40s -> %s\n' "frontend  http://localhost/"            "$(c http://localhost/)"
printf '%-40s -> %s\n' "backend   http://localhost:8081/"       "$(c http://localhost:8081/)"
printf '%-40s -> %s\n' "api-check http://localhost:8081/api-check/" "$(c http://localhost:8081/api-check/)"
[ "$(c http://localhost/)" = "200" ] || fail=1
case "$(c http://localhost:8081/)" in 401|200) ;; *) fail=1 ;; esac
curl -s http://localhost/ | grep -o '<title>[^<]*</title>' || true
echo "-- user default di DB:"
mariadb -N -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" -e "SELECT username, is_superuser FROM auth_user" 2>/dev/null \
  || mariadb -N -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" -e "SHOW TABLES LIKE '%user%'"
echo "-- jumlah tabel ocsv3: $(mariadb -N -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${OCS3_DB_NAME}'")"
echo "-- log uWSGI backend (10 baris terakhir):"
tail -n 10 /var/log/uwsgi/ocsinventory-backend.log 2>/dev/null | grep -v -F "$OCS3_DB_PWD" || true

exit "$fail"
