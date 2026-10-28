#!/bin/bash
# 0015-inspect-ocs3.sh
# Persiapan OCS 3.0.0-rc2. TIDAK memasang OCS 3 dan TIDAK mematikan OCS 2.
# - Cek disk/LVM/RAM terhadap requirement 3.x (RAM min 4 GB, disk kosong min 20 GB)
# - Tambah repo resmi deb-v3.ocsinventory-ng.org (noble)
# - Download paket (tanpa install), tampilkan dependensi, script konfigurasi, nginx & systemd
set -uo pipefail

sec() { echo; echo "##### $* #####"; }

sec "RAM / DISK"
free -h
df -h /
echo "-- LVM:"
pvs 2>/dev/null; vgs 2>/dev/null; lvs 2>/dev/null
echo "-- Disk fisik:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

sec "REPO OCS v3"
curl -fsSL https://deb-v3.ocsinventory-ng.org/repo-signing-key.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/ocs-archive-keyring.gpg
echo "deb https://deb-v3.ocsinventory-ng.org/ noble main" > /etc/apt/sources.list.d/ocsinventory.list
apt-get update -q 2>&1 | grep -i -E 'ocsinventory|err|warn' || true

sec "PAKET"
for p in ocsinventory-server ocsinventory-backend ocsinventory-frontend; do
  echo "--- $p"
  apt-cache show "$p" 2>/dev/null | grep -E '^(Version|Depends|Pre-Depends|Recommends|Conflicts|Installed-Size):' | head -12
done
echo "-- Simulasi install (apa saja yang akan dipasang/dihapus):"
apt-get -s install ocsinventory-server 2>&1 | grep -E '^(Inst|Remv|Conf)' | awk '{print $1, $2, $3}' | head -60

sec "ISI PAKET"
W=/root/ocs3-inspect; rm -rf "$W"; install -d -m 700 "$W"; cd "$W"
apt-get download ocsinventory-backend ocsinventory-frontend ocsinventory-server 2>&1 | tail -3
ls -lh *.deb
for d in *.deb; do
  n=${d%%_*}; mkdir -p "x/$n" "c/$n"
  dpkg-deb -x "$d" "x/$n"; dpkg-deb -e "$d" "c/$n"
done
echo "-- Struktur (tanpa node_modules/site-packages):"
find x -maxdepth 5 \( -name node_modules -o -name site-packages -o -name dist -o -name assets \) -prune -o -print | sed "s|^x/||" | head -120

show() { echo; echo "======== $1"; if [ -f "$1" ]; then cat "$1"; else echo "(tidak ada)"; fi; }
show x/ocsinventory-backend/usr/share/ocsinventory-backend/tools/configure-ocsinventory-backend.sh
for f in c/*/postinst c/*/preinst c/*/prerm; do show "$f"; done
for f in $(find x -path '*nginx*' -type f | head -5); do show "$f"; done
for f in $(find x -name '*.service' -type f | head -5); do show "$f"; done
for f in $(find x -name 'config.json' -path '*frontend*' | head -3); do show "$f"; done
for f in $(find x -name '*.ini' -path '*backend*' | head -3); do show "$f"; done
echo
echo "-- File settings/env backend:"
find x/ocsinventory-backend -maxdepth 6 \( -name '*.env*' -o -name 'settings*.py' -o -name '.env.example' \) | head -10
for f in $(find x/ocsinventory-backend -maxdepth 6 -name '.env*' | head -2); do show "$f"; done

sec "PYTHON & PORT"
python3 --version
ss -tlnp | grep -E ':(80|443|8081|3306|5432)\b' || true

echo
echo "INSPEKSI 3.0 SELESAI (belum ada yang dipasang)"
