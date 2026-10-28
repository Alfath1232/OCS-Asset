#!/bin/bash
# 0008-ocs-schema-retry.sh (ulang 0007; XML::Entities tidak ada di apt noble -> cpanm, tidak fatal)
# - Rapikan warning dari 0006: XML::Entities (SOAP) dan ServerName Apache
# - Jalankan wizard web OCS secara otomatis (install.php -> update ke GUI_VER)
# - Verifikasi versi skema di database
# - Pindahkan install.php ke backup (hardening standar OCS)
# Respons HTML wizard TIDAK dicetak ke log (bisa memuat password DB).
set -euo pipefail

SECRET_FILE=/root/ocsaeon-secrets/ocs-db.env
WEBROOT=/usr/share/ocsinventory-reports/ocsreports
WORK=/root/ocs-install/wizard
BASE=http://localhost/ocsreports
# shellcheck disable=SC1090
. "$SECRET_FILE"

db_ver() {
  mariadb -N -u "$OCS_DB_USER" -p"$OCS_DB_PWD" ocsweb \
    -e "SELECT tvalue FROM config WHERE name='GUI_VERSION'" 2>/dev/null || true
}

echo "== Modul tambahan: XML::Entities (untuk SOAP API, opsional, tidak fatal)"
if perl -MXML::Entities -e1 2>/dev/null; then
  echo "OK XML::Entities (sudah ada)"
else
  apt-get install -y -q cpanminus >/dev/null
  if timeout 600 cpanm --notest -q XML::Entities >/dev/null 2>&1 && perl -MXML::Entities -e1; then
    echo "OK XML::Entities (via cpanm)"
  else
    echo "WARN: XML::Entities gagal dipasang, SOAP API tidak aktif (agent & web console tetap jalan)"
  fi
fi

echo "== ServerName Apache"
echo "ServerName $(hostname)" > /etc/apache2/conf-available/servername.conf
a2enconf -q servername
apache2ctl configtest
systemctl restart apache2
sleep 2

TARGET=$(grep -oP "define\('GUI_VER',\s*'\K[0-9]+" "$WEBROOT/var.php")
echo "== Versi skema yang dibutuhkan web console: $TARGET"
echo "== Versi skema di DB sekarang: $(db_ver || true)"

install -d -m 700 "$WORK"
JAR="$WORK/cookies.txt"
rm -f "$JAR"

if [ -z "$(db_ver)" ]; then
  echo "== Langkah 1: install.php (buat skema dasar)"
  curl -s -c "$JAR" -b "$JAR" -o "$WORK/01-get.html" "$BASE/install.php"
  curl -s -c "$JAR" -b "$JAR" -o "$WORK/02-post.html" -w "HTTP %{http_code}\n" \
    --data-urlencode "name=$OCS_DB_USER" \
    --data-urlencode "pass=$OCS_DB_PWD" \
    --data-urlencode "database=ocsweb" \
    --data-urlencode "host=localhost" \
    --data-urlencode "port=3306" \
    --data-urlencode "enablessl=0" \
    --data-urlencode "sslmode=" \
    --data-urlencode "sslkey=" \
    --data-urlencode "sslcert=" \
    --data-urlencode "cacert=" \
    "$BASE/install.php"
  echo "   versi skema setelah install: $(db_ver)"
fi

for i in 1 2 3; do
  cur=$(db_ver)
  [ "$cur" = "$TARGET" ] && break
  echo "== Langkah 2.$i: update skema $cur -> $TARGET"
  curl -s -c "$JAR" -b "$JAR" -o "$WORK/03-index-$i.html" "$BASE/index.php"
  curl -s -c "$JAR" -b "$JAR" -o "$WORK/04-update-$i.html" -w "HTTP %{http_code}\n" \
    --data-urlencode "update=update" "$BASE/index.php"
  sleep 2
done

cur=$(db_ver)
echo "== Versi skema akhir: ${cur:-KOSONG} (target $TARGET)"
echo "== Jumlah tabel di ocsweb: $(mariadb -N -u "$OCS_DB_USER" -p"$OCS_DB_PWD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='ocsweb'")"

if [ "$cur" != "$TARGET" ]; then
  echo "!! Skema belum sesuai. Potongan teks halaman terakhir (tanpa password):"
  for f in $(ls -t "$WORK"/*.html | head -2); do
    echo "--- $f"
    sed -e 's/<[^>]*>/ /g' "$f" | tr -s ' \n' | grep -v -F "$OCS_DB_PWD" | head -c 1500; echo
  done
  exit 5
fi

echo "== Cek dbconfig.inc.php memakai user ocs (password disamarkan)"
grep -E 'COMPTE_BASE|DB_NAME|SERVER_WRITE' "$WEBROOT/dbconfig.inc.php"
grep -q "PSWD_BASE\",\"$OCS_DB_PWD\"" "$WEBROOT/dbconfig.inc.php" \
  && echo "PSWD_BASE: cocok dengan secret" || { echo "!! PSWD_BASE tidak cocok"; exit 6; }

echo "== Hardening: pindahkan install.php"
if [ -f "$WEBROOT/install.php" ]; then
  mv -v "$WEBROOT/install.php" /root/ocs-install/install.php.bak
fi

echo "== Tes halaman login"
code=$(curl -s -o "$WORK/05-login.html" -w '%{http_code}' "$BASE/index.php")
echo "/ocsreports/index.php -> HTTP $code"
grep -qi 'login\|password\|mot de passe' "$WORK/05-login.html" && echo "Halaman login tampil" || echo "!! halaman login tidak terdeteksi"
rm -f "$JAR"

echo "== Error Apache 10 baris terakhir:"
tail -n 10 /var/log/apache2/error.log | grep -v -F "$OCS_DB_PWD" || true
