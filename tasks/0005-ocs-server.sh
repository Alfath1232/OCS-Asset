#!/bin/bash
# 0005-ocs-server.sh
# Download OCS Inventory Server 2.12.6, verifikasi checksum, jalankan setup.sh
# secara non-interaktif, set password DB di config Apache, aktifkan config.
set -euo pipefail

VER=2.12.6
SHA256=57216f5e20436ed07226bf014deda1c978b3c030a650a02bd57b020f51c954c2
URL="https://github.com/OCSInventory-NG/OCSInventory-ocsreports/releases/download/${VER}/OCSNG_UNIX_SERVER-${VER}.tar.gz"
WORK=/root/ocs-install
SECRET_FILE=/root/ocsaeon-secrets/ocs-db.env

# shellcheck disable=SC1090
. "$SECRET_FILE"

echo "== Download $VER"
install -d -m 700 "$WORK"
cd "$WORK"
curl -fsSL -o "ocs-$VER.tar.gz" "$URL"
echo "${SHA256}  ocs-$VER.tar.gz" | sha256sum -c -
rm -rf "OCSNG_UNIX_SERVER-$VER"
tar xzf "ocs-$VER.tar.gz"
cd "OCSNG_UNIX_SERVER-$VER"

echo "== Jalankan setup.sh (non-interaktif, semua jawaban default)"
# Nilai lewat environment dibaca setup.sh (lihat setup.answers).
# Prompt [y]/n -> Enter = ya. Prompt y/[n] (muncul kalau ada prasyarat hilang) -> Enter = batal.
export DB_SERVER_HOST=localhost
export DB_SERVER_PORT=3306
export DB_SERVER_USER="$OCS_DB_USER"
export DB_SERVER_PWD="$OCS_DB_PWD"
export APACHE_MOD_PERL_VERSION=2
export APACHE_CONFIG_DIRECTORY=/etc/apache2/conf-available
set +e
# bash (bukan sh/dash) karena setup.sh memakai [[ ]] untuk membaca setup.answers
yes '' | timeout 900 bash setup.sh > setup-output.txt 2>&1
rc=${PIPESTATUS[1]}
set -e
# Tampilkan output tanpa baris yang memuat password
grep -v -F "$OCS_DB_PWD" setup-output.txt | tail -n 120
if [ "$rc" -ne 0 ]; then
  echo "!! setup.sh exit $rc"
  echo "== 60 baris terakhir ocs_server_setup.log:"
  grep -v -F "$OCS_DB_PWD" ocs_server_setup.log | tail -n 60 || true
  exit "$rc"
fi

CONF_SRV=/etc/apache2/conf-available/z-ocsinventory-server.conf
CONF_API=/etc/apache2/conf-available/zz-ocsinventory-restapi.conf
CONF_WEB=/etc/apache2/conf-available/ocsinventory-reports.conf

echo "== File config yang dibuat setup.sh:"
ls -l "$CONF_SRV" "$CONF_API" "$CONF_WEB"

echo "== Set password DB di config Communication server & REST API"
sed -i -E "s|^(\s*PerlSetVar\s+OCS_DB_PWD\s+).*|\1${OCS_DB_PWD}|" "$CONF_SRV"
sed -i -E "s|^(\s*\\\$ENV\{OCS_DB_PWD\}\s*=\s*)'.*';|\1'${OCS_DB_PWD}';|" "$CONF_API"
chmod 640 "$CONF_SRV" "$CONF_API"
chown root:www-data "$CONF_SRV" "$CONF_API"

echo "== Verifikasi (password disamarkan)"
grep -E 'OCS_DB_(HOST|PORT|NAME|USER|PWD)' "$CONF_SRV" | sed -E 's/(OCS_DB_PWD\s+).*/\1********/'
grep -E 'OCS_DB_(HOST|PORT|NAME|USER|PWD)' "$CONF_API" | sed -E "s/(OCS_DB_PWD\} = ).*/\1'********';/"
if grep -qE 'OCS_DB_PWD\s+ocs$' "$CONF_SRV" || grep -q "OCS_DB_PWD} = 'ocs';" "$CONF_API"; then
  echo "!! Password default 'ocs' masih ada di config"; exit 1
fi

echo "== Aktifkan config Apache"
a2enconf ocsinventory-reports z-ocsinventory-server zz-ocsinventory-restapi
chown -R www-data:www-data /var/lib/ocsinventory-reports
apache2ctl configtest
systemctl restart apache2
systemctl is-active apache2

echo "== Tes HTTP lokal"
sleep 2
for p in /ocsreports/ /ocsreports/install.php /ocsinventory; do
  printf '%-28s -> HTTP %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost$p")"
done

echo "== Error Apache terbaru (kalau ada):"
tail -n 20 /var/log/apache2/error.log | grep -v -F "$OCS_DB_PWD" || true
