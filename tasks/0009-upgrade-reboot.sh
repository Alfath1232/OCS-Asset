#!/bin/bash
# 0009-upgrade-reboot.sh  (DISRUPTIF: server reboot ~1-2 menit)
# - Pastikan service penting auto-start setelah boot; kalau tidak, BATAL reboot
# - apt full-upgrade (kernel + firmware yang tertahan di 0002)
# - Jadwalkan reboot 90 detik SETELAH task ini selesai, supaya runner sempat push log
#   (reboot langsung di dalam task -> log hilang & task bisa jalan ulang = reboot loop)
# Rollback kernel: menu GRUB -> Advanced options -> pilih kernel lama.
set -euo pipefail

echo "== Kernel aktif sebelum: $(uname -r)"

echo "== Cek service auto-start (wajib enabled sebelum reboot)"
fail=0
for u in ssh tailscaled apache2 mariadb ocsaeon-runner.timer; do
  st=$(systemctl is-enabled "$u" 2>/dev/null || true)
  printf '%-24s %s\n' "$u" "${st:-tidak-ada}"
  case "$st" in enabled|enabled-runtime|static|alias|indirect) ;; *) fail=1 ;; esac
done
# ssh di Ubuntu 24.04 bisa via socket activation
if [ "$fail" -ne 0 ] && systemctl is-enabled ssh.socket >/dev/null 2>&1; then
  echo "ssh.socket enabled (socket activation)"
  fail=0
  for u in tailscaled apache2 mariadb ocsaeon-runner.timer; do
    systemctl is-enabled "$u" >/dev/null 2>&1 || fail=1
  done
fi
if [ "$fail" -ne 0 ]; then
  echo "!! Ada service penting yang tidak enabled. REBOOT DIBATALKAN."
  exit 1
fi

echo "== apt full-upgrade"
apt-get update -q
apt-get -y -q \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  full-upgrade
apt-get -y -q autoremove

echo "== Kernel terpasang:"
dpkg -l 'linux-image-[0-9]*' | awk '/^ii/{print $2, $3}'

echo "== Sisa paket upgradable:"
apt list --upgradable 2>/dev/null | tail -n +2 || true

echo "== Jadwalkan reboot 90 detik lagi"
systemd-run --unit=ocsaeon-reboot --on-active=90 /bin/systemctl reboot
systemctl list-timers ocsaeon-reboot.timer --no-pager || true
echo "Reboot terjadwal. Server akan mati sebentar."
