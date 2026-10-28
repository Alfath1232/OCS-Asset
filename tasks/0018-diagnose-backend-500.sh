#!/bin/bash
# 0018-diagnose-backend-500.sh — DIAGNOSA SAJA, tidak mengubah config.
# Backend OCS 3 (:8081) membalas HTTP 500. Kumpulkan log & traceback.
set -uo pipefail
sec() { echo; echo "##### $* #####"; }

B=/usr/share/ocsinventory-backend
VENV=/usr/lib/ocsinventory-backend/venv
. /root/ocsaeon-secrets/ocs3-db.env
mask() {
  local s1 s2
  s1=$(grep -oP "^SECRET_KEY='\K[^']+" "$B/.env" 2>/dev/null || true)
  s2=$(grep -oP "^FIELD_ENCRYPTION_KEY='\K[^']+" "$B/.env" 2>/dev/null || true)
  sed -e "s|${OCS3_DB_PWD}|****DBPWD****|g" \
      ${s1:+-e "s|${s1}|****SECRET****|g"} \
      ${s2:+-e "s|${s2}|****FKEY****|g"}
}

sec "REQUEST ULANG"
for p in / /api-check/; do
  printf '%-14s -> %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8081$p")"
done

sec "PROSES uWSGI"
ps -o user,pid,cmd -C uwsgi | head -10
ls -l /var/run/uwsgi/app/ocsinventory-backend/ 2>/dev/null

sec "LOG FILES"
for f in /var/log/uwsgi/ocsinventory-backend.log /var/log/uwsgi/app/ocsinventory-backend.log \
         /var/log/ocsinventory-backend/*.log "$B"/logs/*.log /var/log/nginx/error.log; do
  [ -f "$f" ] || continue
  echo "======== $f ($(stat -c '%U:%G %a' "$f"))"
  tail -n 40 "$f" | mask
done
echo "-- isi folder logs backend:"; ls -la "$B/logs" 2>/dev/null

sec "PERMISSION"
ls -la "$B" | head -12
stat -c '%U:%G %a %n' "$B/.env"

sec "DJANGO CHECK (sebagai www-data)"
cd "$B"
sudo -u www-data "$VENV/bin/python3" manage.py check 2>&1 | mask | tail -n 30

sec "TEST CLIENT: GET / dan /api-check/ (traceback)"
sudo -u www-data "$VENV/bin/python3" - <<'PY' 2>&1 | mask | tail -n 80
import os, sys, traceback
sys.path.insert(0, "/usr/share/ocsinventory-backend")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "ocsinventory_backend.settings")
import django
django.setup()
from django.conf import settings
settings.ALLOWED_HOSTS = ["*"]
from django.test import Client
c = Client(raise_request_exception=True)
for path in ["/", "/api-check/"]:
    print(f"--- GET {path}")
    try:
        r = c.get(path, HTTP_HOST="localhost:8081")
        print("status", r.status_code, r.content[:300])
    except Exception:
        traceback.print_exc()
PY

sec "VERSI PAKET PYTHON"
"$VENV/bin/pip" list 2>/dev/null | grep -i -E '^(django |djangorestframework |django-rest-knox|mysqlclient|cryptography|django-cors|drf-spectacular)'

echo
echo "DIAGNOSA SELESAI"
