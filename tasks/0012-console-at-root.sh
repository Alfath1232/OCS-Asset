#!/bin/bash
# 0012-console-at-root.sh
# Web console OCS diakses langsung di http://<server>/ (tanpa /ocsreports).
# - VirtualHost baru: DocumentRoot = folder ocsreports
# - /ocsreports/... di-redirect 301 ke /...  (bookmark lama tetap jalan)
# - /ocsinventory (agent), /download, /snmp, /ocsapi tidak berubah (config global)
# - Batas upload PHP 8 (mod_php.c) untuk deploy paket, karena config bawaan OCS hanya php5/php7
#
# Rollback:
#   a2dissite ocsaeon && a2ensite 000-default && systemctl reload apache2
set -euo pipefail

WEBROOT=/usr/share/ocsinventory-reports/ocsreports
SITE=/etc/apache2/sites-available/ocsaeon.conf

echo "== Site aktif sebelum:"
ls -l /etc/apache2/sites-enabled/

echo "== Tulis $SITE"
cat > "$SITE" <<CONF
# OCS AEON — web console di root URL (dikelola repo itcnelita/ocsaeon, task 0012)
<VirtualHost *:80>
    ServerName $(hostname)
    DocumentRoot $WEBROOT

    # URL lama /ocsreports -> URL baru di root
    RedirectMatch 301 ^/ocsreports(/(.*))?\$ /\$2

    <Directory $WEBROOT>
        Require all granted
        Options FollowSymLinks
        DirectoryIndex index.php
        AllowOverride Options AuthConfig
        <IfModule mod_php.c>
            php_flag  file_uploads        on
            php_value post_max_size       101M
            php_value upload_max_filesize 100M
        </IfModule>
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
CONF
cat "$SITE"

echo "== Ganti site default -> ocsaeon"
a2ensite -q ocsaeon
a2dissite -q 000-default || true
if ! apache2ctl configtest; then
  echo "!! configtest gagal, rollback"
  a2dissite -q ocsaeon; a2ensite -q 000-default
  exit 1
fi
systemctl reload apache2
sleep 2
ls -l /etc/apache2/sites-enabled/

echo "== Verifikasi"
fail=0
check() { # path, kode yang diharapkan
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost$1")
  printf '%-26s -> HTTP %s (harap %s)\n' "$1" "$code" "$2"
  [ "$code" = "$2" ] || fail=1
}
check /                       200
check /index.php              200
check /themes/AEON/logo.png   200
check /favicon.ico            200
check /ocsreports/            301
check /ocsinventory           400
printf 'Redirect /ocsreports/  -> %s\n' "$(curl -s -o /dev/null -w '%{redirect_url}' http://localhost/ocsreports/)"
printf 'Redirect /ocsreports/index.php -> %s\n' "$(curl -s -o /dev/null -w '%{redirect_url}' http://localhost/ocsreports/index.php)"
curl -s http://localhost/ | grep -q 'themes/AEON/' && echo "Root menampilkan console OCS tema AEON: OK" || { echo "!! root bukan console OCS"; fail=1; }

echo "== Batas upload PHP yang berlaku di console:"
cat > "$WEBROOT/.ocsaeon-phpcheck.php" <<'PHP'
<?php echo ini_get('upload_max_filesize'), ' / ', ini_get('post_max_size');
PHP
echo "upload_max_filesize / post_max_size = $(curl -s http://localhost/.ocsaeon-phpcheck.php)"
rm -f "$WEBROOT/.ocsaeon-phpcheck.php"

echo "== Error Apache terbaru:"
tail -n 5 /var/log/apache2/error.log || true

exit "$fail"
