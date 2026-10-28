#!/bin/bash
# 0014-backup-ocs2.sh
# Backup penuh OCS 2.12.6 sebelum diganti ke 3.0.0-rc2 (bekal rollback).
# Hasil di /root/ocs-backup/<timestamp>/  (TIDAK di-push ke GitHub: berisi data & secret)
set -euo pipefail

TS=$(date +%Y%m%d-%H%M%S)
DIR=/root/ocs-backup/ocs2-$TS
install -d -m 700 "$DIR"
. /root/ocsaeon-secrets/ocs-db.env

echo "== Dump database ocsweb"
mariadb-dump --single-transaction --routines --triggers ocsweb | gzip > "$DIR/ocsweb.sql.gz"
gzip -t "$DIR/ocsweb.sql.gz" && echo "dump OK"
echo "Jumlah tabel di dump: $(zcat "$DIR/ocsweb.sql.gz" | grep -c '^CREATE TABLE')"

echo "== Arsip config & file OCS 2.x"
tar -czf "$DIR/ocs2-files.tar.gz" \
  /etc/apache2 \
  /etc/ocsinventory-server \
  /usr/share/ocsinventory-reports \
  /var/lib/ocsinventory-reports \
  /etc/logrotate.d/ocsinventory-server \
  /root/ocsaeon-secrets \
  2>/dev/null || true
tar -tzf "$DIR/ocs2-files.tar.gz" >/dev/null && echo "arsip OK"

echo "== Daftar paket terpasang (untuk reinstall bila rollback)"
dpkg --get-selections > "$DIR/dpkg-selections.txt"

chmod -R go-rwx "$DIR"
echo "== Isi backup:"
ls -lh "$DIR"
du -sh "$DIR"
echo "Lokasi backup: $DIR"
