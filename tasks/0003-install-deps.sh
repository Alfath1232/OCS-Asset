#!/bin/bash
# 0003-install-deps.sh
# Pasang Apache + mod_perl, MariaDB, PHP 8.3 dan modul Perl yang dicek setup.sh OCS 2.12.6.
# Semua dari repo apt Ubuntu 24.04 (tanpa cpanm).
set -euo pipefail

apt-get install -y -q \
  apache2 libapache2-mod-perl2 libapache2-mod-php \
  mariadb-server mariadb-client \
  php php-mysql php-zip php-gd php-mbstring php-curl php-xml php-soap php-intl \
  make perl \
  libdbi-perl libdbd-mysql-perl libapache-dbi-perl \
  libxml-simple-perl libio-compress-perl libnet-ip-perl libarchive-zip-perl \
  libswitch-perl libmojolicious-perl libplack-perl libyaml-perl libsoap-lite-perl

echo
echo "== Cek modul Perl yang dibutuhkan setup.sh"
fail=0
for m in DBI DBD::mysql Apache::DBI Compress::Zlib XML::Simple Net::IP Archive::Zip \
         Mojolicious::Lite Plack::Handler Switch YAML mod_perl2; do
  if perl -m"$m" -e1 2>/dev/null; then
    echo "OK    $m"
  else
    echo "HILANG $m"; fail=1
  fi
done

echo
echo "== Versi"
apache2 -v | head -1
mariadb --version
php -v | head -1

echo
echo "== Service"
systemctl enable --now apache2 mariadb
systemctl is-active apache2 mariadb

echo
echo "== Modul Apache perl & php aktif?"
apache2ctl -M 2>/dev/null | grep -E 'perl_module|php' || { echo "modul belum aktif"; fail=1; }

exit $fail
