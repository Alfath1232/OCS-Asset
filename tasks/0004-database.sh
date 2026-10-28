#!/bin/bash
# 0004-database.sh
# Buat database ocsweb + user ocs dengan password acak.
# Password DISIMPAN DI SERVER SAJA: /root/ocsaeon-secrets/ocs-db.env (chmod 600).
# Password TIDAK dicetak ke log (log ini ter-push ke GitHub).
set -euo pipefail

SECRETS_DIR=/root/ocsaeon-secrets
SECRET_FILE=$SECRETS_DIR/ocs-db.env

install -d -m 700 "$SECRETS_DIR"

if [ -f "$SECRET_FILE" ]; then
  echo "== Secret sudah ada, pakai yang lama"
else
  echo "== Generate password DB baru (hex 32 karakter, tanpa simbol)"
  umask 077
  printf 'OCS_DB_USER=ocs\nOCS_DB_PWD=%s\n' "$(openssl rand -hex 16)" > "$SECRET_FILE"
fi
chmod 600 "$SECRET_FILE"
# shellcheck disable=SC1090
. "$SECRET_FILE"

echo "== Buat database & user (via socket root MariaDB)"
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS ocsweb CHARACTER SET utf8mb3 COLLATE utf8mb3_bin;
CREATE USER IF NOT EXISTS 'ocs'@'localhost' IDENTIFIED BY '${OCS_DB_PWD}';
ALTER USER 'ocs'@'localhost' IDENTIFIED BY '${OCS_DB_PWD}';
GRANT ALL PRIVILEGES ON ocsweb.* TO 'ocs'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "== Tes login sebagai user ocs"
mariadb -u ocs -p"$OCS_DB_PWD" -e "SELECT CURRENT_USER() AS login_ok; SHOW DATABASES LIKE 'ocsweb';"

echo "== Pastikan MariaDB hanya listen di localhost"
ss -tlnp | grep -E ':3306' || true

echo "== Password tersimpan di $SECRET_FILE (lihat via SSH: sudo cat $SECRET_FILE)"
