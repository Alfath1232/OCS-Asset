#!/bin/bash
# 0002-prepare-system.sh
# - Timezone ke Asia/Jakarta (supaya waktu inventaris di OCS sesuai jam kantor)
# - apt update + upgrade paket yang tertunda (252 paket saat inspeksi)
# TIDAK reboot otomatis. Kalau kernel ter-update, reboot dilakukan manual.
set -euo pipefail

echo "== Timezone sebelum: $(timedatectl show -p Timezone --value)"
timedatectl set-timezone Asia/Jakarta
echo "== Timezone sesudah: $(timedatectl show -p Timezone --value)"

echo "== apt update"
apt-get update -q

echo "== apt upgrade (pertahankan config lama kalau ada konflik)"
apt-get -y -q \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  upgrade

echo "== sisa paket yang bisa di-upgrade:"
apt list --upgradable 2>/dev/null | tail -n +2 || true

if [ -f /var/run/reboot-required ]; then
  echo "!! REBOOT DIPERLUKAN (dilakukan manual nanti):"
  cat /var/run/reboot-required.pkgs 2>/dev/null || true
else
  echo "== Tidak perlu reboot"
fi
