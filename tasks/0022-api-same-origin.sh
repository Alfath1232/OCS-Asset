#!/bin/bash
# 0022-api-same-origin.sh
# Console dibuka lewat https://ocsaeon.itcnelita.com (TLS di proxy 192.168.100.110),
# frontend memanggil API http://...:8081 -> diblokir browser (mixed content).
# Solusi: API juga dilayani di origin yang sama: https://ocsaeon.itcnelita.com/api/
#   - nginx frontend: location /api/ -> uWSGI backend (SCRIPT_NAME=/api, scheme dari X-Forwarded-Proto)
#   - config.json frontend -> https://ocsaeon.itcnelita.com/api/
#   - FRONTEND_REDIRECT backend -> https://ocsaeon.itcnelita.com
# Port 8081 tetap ada (agent / akses langsung).
#
# Rollback:
#   cp /root/ocs-install/ocs3-frontend-site.bak-0022 /etc/nginx/sites-available/ocsinventory-frontend
#   cp /root/ocs-install/ocs3-config.json.bak-0022 /usr/share/ocsinventory-frontend/config/config.json
#   systemctl reload nginx
set -euo pipefail

DOMAIN=ocsaeon.itcnelita.com
SITE=/etc/nginx/sites-available/ocsinventory-frontend
CFG=/usr/share/ocsinventory-frontend/config/config.json
ENVF=/usr/share/ocsinventory-backend/.env
SOCK=/var/run/uwsgi/app/ocsinventory-backend/socket

echo "== Backup"
install -d -m 700 /root/ocs-install
[ -f /root/ocs-install/ocs3-frontend-site.bak-0022 ] || cp -v "$SITE" /root/ocs-install/ocs3-frontend-site.bak-0022
[ -f /root/ocs-install/ocs3-config.json.bak-0022 ]   || cp -v "$CFG"  /root/ocs-install/ocs3-config.json.bak-0022

echo "== Tulis site nginx frontend + proxy /api"
cat > "$SITE" <<NGINX
# OCS 3 frontend + API di origin yang sama (dikelola repo itcnelita/ocsaeon, task 0022)
map \$http_x_forwarded_proto \$ocs_scheme { default \$scheme; https https; http http; }
map \$ocs_scheme \$ocs_https { default ""; https on; }

server {
    listen 80;
    server_name _;

    root /usr/share/ocsinventory-frontend;
    index index.html;

    access_log /var/log/ocsinventory-frontend/access.log;
    error_log /var/log/ocsinventory-frontend/error.log;

    client_max_body_size 100m;

    # Backend API di /api/... (prefix dihapus sebelum masuk Django lewat SCRIPT_NAME)
    location ~ ^/api(?<ocs_path>/.*)?\$ {
        if (\$ocs_path = "") { return 301 /api/; }
        uwsgi_pass unix:${SOCK};
        uwsgi_param QUERY_STRING    \$query_string;
        uwsgi_param REQUEST_METHOD  \$request_method;
        uwsgi_param CONTENT_TYPE    \$content_type;
        uwsgi_param CONTENT_LENGTH  \$content_length;
        uwsgi_param REQUEST_URI     \$request_uri;
        uwsgi_param SCRIPT_NAME     /api;
        uwsgi_param PATH_INFO       \$ocs_path;
        uwsgi_param DOCUMENT_ROOT   \$document_root;
        uwsgi_param SERVER_PROTOCOL \$server_protocol;
        uwsgi_param REQUEST_SCHEME  \$ocs_scheme;
        uwsgi_param UWSGI_SCHEME    \$ocs_scheme;
        uwsgi_param HTTPS           \$ocs_https if_not_empty;
        uwsgi_param REMOTE_ADDR     \$remote_addr;
        uwsgi_param REMOTE_PORT     \$remote_port;
        uwsgi_param SERVER_ADDR     \$server_addr;
        uwsgi_param SERVER_PORT     \$server_port;
        uwsgi_param SERVER_NAME     \$host;
        uwsgi_read_timeout 300;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX

if ! nginx -t 2>&1; then
  echo "!! nginx -t gagal, rollback"
  cp /root/ocs-install/ocs3-frontend-site.bak-0022 "$SITE"
  exit 1
fi

echo "== config.json frontend"
cat > "$CFG" <<JSON
{
  "BACKEND_API_ROUTE": "https://${DOMAIN}/api/"
}
JSON
chown www-data: "$CFG"; chmod 644 "$CFG"
cat "$CFG"

echo "== FRONTEND_REDIRECT backend"
sed -i "s|^FRONTEND_REDIRECT=.*|FRONTEND_REDIRECT='https://${DOMAIN}'|" "$ENVF"
grep '^FRONTEND_REDIRECT=' "$ENVF"

systemctl reload nginx
systemctl restart uwsgi
sleep 4

echo "== Verifikasi (meniru request dari proxy HTTPS)"
fail=0
H=(-H "Host: ${DOMAIN}" -H "X-Forwarded-Proto: https")
c() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
r1=$(c "${H[@]}" http://localhost/api/api-check/)
r2=$(c "${H[@]}" http://localhost/api/)
r3=$(c "${H[@]}" http://localhost/)
r4=$(c http://localhost:8081/api-check/)
printf '%-36s -> %s (harap 200)\n' "/api/api-check/"        "$r1"
printf '%-36s -> %s (harap 401)\n' "/api/"                  "$r2"
printf '%-36s -> %s (harap 200)\n' "/ (frontend)"           "$r3"
printf '%-36s -> %s (harap 200)\n' ":8081/api-check/ (tetap)" "$r4"
[ "$r1" = "200" ] || fail=1; [ "$r3" = "200" ] || fail=1; [ "$r4" = "200" ] || fail=1
case "$r2" in 401|200) ;; *) fail=1 ;; esac
echo "-- isi: $(curl -s "${H[@]}" http://localhost/api/api-check/)"
echo "-- config.json via frontend: $(curl -s "${H[@]}" http://localhost/config/config.json | tr -d '\n ')"

echo "-- tes token + URL absolut yang dibuat Django:"
TOKEN=$(curl -s "${H[@]}" -X POST -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' http://localhost/api/api-auth/token \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("token",""))' 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
  echo "token: OK (disamarkan)"
  curl -s "${H[@]}" -H "Authorization: Token $TOKEN" http://localhost/api/ | python3 -c '
import sys,json
try:
    d=json.load(sys.stdin); items=list(d.items())[:4]
    for k,v in items: print(" ",k,"->",v)
except Exception as e: print("  (bukan JSON)", e)'
  curl -s "${H[@]}" -H "Authorization: Token $TOKEN" -X POST http://localhost/api/api-auth/token/logout -o /dev/null || true
else
  echo "!! token tidak didapat"; fail=1
fi
echo "-- tes /api/login/ dengan Origin HTTPS (status saja):"
c "${H[@]}" -H "Origin: https://${DOMAIN}" -H "Referer: https://${DOMAIN}/" -X POST \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}' http://localhost/api/login/; echo

exit "$fail"
