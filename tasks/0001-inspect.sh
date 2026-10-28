#!/bin/bash
# 0001-inspect.sh — CEK SAJA, tidak mengubah apa pun.
# Tujuan: tahu kondisi server sebelum install OCS (OS, resource, jaringan, port, paket).

sec() { echo; echo "##### $* #####"; }

sec "OS"
cat /etc/os-release | head -5
uname -r

sec "CPU / RAM / DISK"
echo "CPU core: $(nproc)"
free -h
df -h / /var /tmp 2>/dev/null | sort -u

sec "IP & ROUTE"
ip -br a
ip route

sec "DNS"
resolvectl status 2>/dev/null | grep -E "DNS Servers|Current DNS" || cat /etc/resolv.conf

sec "INTERNET"
ping -c 2 -W 2 1.1.1.1 && echo "PING IP: OK" || echo "PING IP: GAGAL"
ping -c 2 -W 2 github.com >/dev/null && echo "DNS+PING github.com: OK" || echo "DNS+PING github.com: GAGAL"
curl -sS -o /dev/null -w "HTTPS api.github.com: %{http_code}\n" https://api.github.com || echo "HTTPS api.github.com: GAGAL"

sec "WAKTU"
timedatectl | grep -E "Local time|Time zone|synchronized"

sec "PORT YANG LISTEN"
ss -tlnp

sec "FIREWALL"
ufw status 2>/dev/null || echo "ufw tidak terpasang"

sec "PAKET TERKAIT (sudah terpasang?)"
for p in apache2 nginx mariadb-server mysql-server php perl libapache2-mod-perl2 cpanminus git; do
  if dpkg -s "$p" >/dev/null 2>&1; then
    echo "TERPASANG : $p $(dpkg-query -W -f='${Version}' "$p")"
  else
    echo "belum     : $p"
  fi
done
php -v 2>/dev/null | head -1
perl -v 2>/dev/null | sed -n 2p

sec "VERSI PHP YANG TERSEDIA DI REPO APT"
apt-cache policy php 2>/dev/null | head -4

sec "OCS RELEASE TERBARU (GitHub)"
curl -s https://api.github.com/repos/OCSInventory-NG/OCSInventory-ocsreports/releases/latest \
  | grep -E '"tag_name"|"published_at"' || echo "gagal cek"

sec "APT LOCK / UPDATE PENDING"
fuser /var/lib/dpkg/lock-frontend 2>/dev/null && echo "dpkg sedang dipakai proses lain" || echo "dpkg bebas"
apt list --upgradable 2>/dev/null | tail -n +2 | wc -l | xargs echo "Paket bisa di-upgrade:"

echo
echo "INSPEKSI SELESAI"
