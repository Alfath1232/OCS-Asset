#!/bin/bash
# 0036-asset-id-fields.sh
# Custom field AEON + Asset ID otomatis (AEON-IT-000001, ...).
# - Backup tabel accountinfo dulu
# - Jalankan aeon/assign_asset_id.py (dry-run lalu sungguhan)
# - Pasang systemd timer: aset baru otomatis dapat Asset ID tiap 10 menit
#
# Rollback data: mariadb ocsv3 < /root/ocs-backup/accountinfo-<waktu>.sql
# Matikan otomatis: systemctl disable --now ocsaeon-assetid.timer
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
B=/usr/share/ocsinventory-backend
VENV=/usr/lib/ocsinventory-backend/venv
LIB=/usr/local/lib/ocsaeon
. /root/ocsaeon-secrets/ocs3-db.env

echo "== Backup tabel accountinfo"
install -d -m 700 /root/ocs-backup
BK=/root/ocs-backup/accountinfo-$(date +%Y%m%d-%H%M%S).sql
mariadb-dump --single-transaction "$OCS3_DB_NAME" \
  accountinfo_accountinfoconfig accountinfo_accountinfovalue accountinfo_accountinfodata > "$BK"
chmod 600 "$BK"; ls -l "$BK"

echo "== Pasang script"
install -d -m 755 "$LIB"
install -m 644 "$REPO_DIR/aeon/assign_asset_id.py" "$LIB/assign_asset_id.py"

echo "== Dry-run"
(cd "$B" && sudo -u www-data AEON_DRY_RUN=1 "$VENV/bin/python3" manage.py shell \
  -c "exec(open('$LIB/assign_asset_id.py').read())" 2>&1 | grep -v 'objects imported')

echo "== Jalankan"
(cd "$B" && sudo -u www-data "$VENV/bin/python3" manage.py shell \
  -c "exec(open('$LIB/assign_asset_id.py').read())" 2>&1 | grep -v 'objects imported')

echo "== Jalankan ulang (harus tidak ada perubahan)"
(cd "$B" && sudo -u www-data "$VENV/bin/python3" manage.py shell \
  -c "exec(open('$LIB/assign_asset_id.py').read())" 2>&1 | grep -v 'objects imported')

echo "== systemd timer tiap 10 menit"
cat > /etc/systemd/system/ocsaeon-assetid.service <<UNIT
[Unit]
Description=OCS AEON - beri Asset ID untuk aset baru
After=mariadb.service

[Service]
Type=oneshot
User=www-data
WorkingDirectory=$B
ExecStart=$VENV/bin/python3 manage.py shell -c "exec(open('$LIB/assign_asset_id.py').read())"
UNIT
cat > /etc/systemd/system/ocsaeon-assetid.timer <<'UNIT'
[Unit]
Description=OCS AEON - Asset ID otomatis tiap 10 menit

[Timer]
OnBootSec=3min
OnUnitActiveSec=10min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now ocsaeon-assetid.timer
systemctl start ocsaeon-assetid.service
systemctl --no-pager --lines=0 status ocsaeon-assetid.service | head -5 || true
journalctl -u ocsaeon-assetid.service -n 3 --no-pager | grep -v 'objects imported' || true

echo "== Verifikasi"
q() { mariadb -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" "$@" 2>&1 | grep -v -F "$OCS3_DB_PWD"; }
q -e "SELECT c.id, c.name, c.datatype, GROUP_CONCAT(v.value ORDER BY v.id SEPARATOR ', ') AS pilihan
      FROM accountinfo_accountinfoconfig c LEFT JOIN accountinfo_accountinfovalue v ON v.accountinfo_config_id=c.id
      GROUP BY c.id ORDER BY c.id"
q -e "SELECT d.object_id AS aset, b.name, d.accountdata FROM accountinfo_accountinfodata d
      JOIN inventory_base_inventorybase b ON b.id=d.object_id ORDER BY d.object_id"
systemctl list-timers ocsaeon-assetid.timer --no-pager | head -3
