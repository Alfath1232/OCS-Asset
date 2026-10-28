#!/bin/bash
# 0021-diagnose-frontend-api.sh — DIAGNOSA SAJA.
# Frontend menampilkan "Oops, something went wrong" sebelum login dan tidak ada
# request browser yang sampai ke backend :8081.
set -uo pipefail
sec() { echo; echo "##### $* #####"; }
F=/usr/share/ocsinventory-frontend

sec "AKSES BROWSER KE FRONTEND (port 80) — 40 terakhir"
tail -n 40 /var/log/ocsinventory-frontend/access.log 2>/dev/null | sed -E 's/"Mozilla[^"]*"/"UA"/'

sec "AKSES KE BACKEND (port 8081) via nginx — 40 terakhir"
tail -n 40 /var/log/nginx/access.log 2>/dev/null | sed -E 's/"Mozilla[^"]*"/"UA"/'

sec "IP UNIK YANG MENGAKSES"
echo "-- frontend:"; awk '{print $1}' /var/log/ocsinventory-frontend/access.log 2>/dev/null | sort | uniq -c
echo "-- backend :"; awk '{print $1}' /var/log/nginx/access.log 2>/dev/null | sort | uniq -c

sec "KONEKTIVITAS KE BACKEND"
for u in http://127.0.0.1:8081/api-check/ http://192.168.100.122:8081/api-check/ http://100.105.251.78:8081/api-check/; do
  printf '%-44s -> %s\n' "$u" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$u")"
done
echo "-- CORS preflight dari origin frontend:"
curl -s -m 5 -i -X OPTIONS http://100.105.251.78:8081/api-check/ \
  -H 'Origin: http://100.105.251.78' -H 'Access-Control-Request-Method: GET' \
  -H 'Access-Control-Request-Headers: authorization,content-type' | grep -i -E '^HTTP|^access-control' || true
echo "-- firewall:"; ufw status 2>/dev/null | head -3; iptables -S INPUT 2>/dev/null | head -5
echo "-- tailscale serve/funnel:"; tailscale serve status 2>/dev/null | head -5 || true

sec "CONFIG FRONTEND"
ls -la "$F/config/"
cat "$F/config/config.json"
echo
printf 'GET /config/config.json lewat nginx -> %s\n' "$(curl -s -o /dev/null -w '%{http_code}' http://localhost/config/config.json)"
curl -s http://localhost/config/config.json; echo

sec "BAGAIMANA BUNDLE JS MEMBACA ALAMAT API"
ls -la "$F" | head -20
ls "$F/assets" 2>/dev/null | head -10
for js in $(find "$F" -name '*.js' -size +20k | head -8); do
  hits=$(grep -o -E '.{80}(config\.json|BACKEND_API_ROUTE|127\.0\.0\.1|localhost:8081|baseURL).{80}' "$js" | head -6)
  [ -n "$hits" ] && { echo "======== $js"; echo "$hits"; }
done
echo "-- index.html:"; head -c 1500 "$F/index.html"; echo

echo
echo "DIAGNOSA SELESAI"
