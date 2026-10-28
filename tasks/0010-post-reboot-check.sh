#!/bin/bash
# 0010-post-reboot-check.sh — CEK SAJA setelah reboot 0009.
set -uo pipefail

sec() { echo; echo "##### $* #####"; }
fail=0

sec "BOOT"
echo "Kernel aktif : $(uname -r)"
echo "Uptime       : $(uptime -p)  (boot: $(uptime -s))"
if [ "$(uptime -s | cut -c1-10)" != "$(date +%F)" ] || [ "$(cut -d. -f1 /proc/uptime)" -gt 3600 ]; then
  echo "!! Sepertinya server BELUM reboot"; fail=1
fi
[ -f /var/run/reboot-required ] && echo "!! masih ada reboot-required" || echo "reboot-required: tidak ada"

sec "SERVICE"
for u in tailscaled apache2 mariadb ssh.socket ocsaeon-runner.timer; do
  st=$(systemctl is-active "$u" 2>/dev/null)
  printf '%-22s %s\n' "$u" "$st"
  [ "$st" = "active" ] || fail=1
done
echo "Gagal (failed units):"; systemctl --failed --no-legend --no-pager || true

sec "JARINGAN"
ip -br a | grep -E 'ens|tailscale'
tailscale status 2>/dev/null | head -3 || true

sec "OCS"
. /root/ocsaeon-secrets/ocs-db.env
printf 'GUI_VERSION DB : %s\n' "$(mariadb -N -u "$OCS_DB_USER" -p"$OCS_DB_PWD" ocsweb -e "SELECT tvalue FROM config WHERE name='GUI_VERSION'" 2>/dev/null)"
for p in /ocsreports/ /ocsinventory; do
  printf '%-14s -> HTTP %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost$p")"
done
code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost/ocsreports/")
[ "$code" = "200" ] || fail=1

sec "ERROR APACHE SEJAK BOOT"
journalctl -u apache2 -b --no-pager -p warning | tail -n 10 || true

echo
[ "$fail" -eq 0 ] && echo "SEMUA OK" || echo "ADA YANG PERLU DICEK"
exit "$fail"
