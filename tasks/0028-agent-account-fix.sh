#!/bin/bash
# 0028-agent-account-fix.sh
# Perbaikan 0027: sudo -u www-data membuang env -> username/password agent tidak sampai.
# Sekarang env dibawa eksplisit dengan --preserve-env (tidak muncul di argumen proses).
set -uo pipefail
sec() { echo; echo "##### $* #####"; }

B=/usr/share/ocsinventory-backend
VENV=/usr/lib/ocsinventory-backend/venv
SECRET=/root/ocsaeon-secrets/ocs3-agent.env
. "$SECRET"
export OCS_AGENT_USER OCS_AGENT_PWD

sec "BUAT / PERBARUI AKUN AGENT"
(cd "$B" && sudo --preserve-env=OCS_AGENT_USER,OCS_AGENT_PWD -u www-data "$VENV/bin/python3" manage.py shell -c "
import os
from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
U = get_user_model()
u, created = U.objects.get_or_create(username=os.environ['OCS_AGENT_USER'])
u.set_password(os.environ['OCS_AGENT_PWD'])
u.is_staff = False; u.is_superuser = False; u.is_active = True
u.first_name = 'OCS'; u.last_name = 'Agent'
u.save()
u.groups.set([Group.objects.get(name='AgentInventory')])
print('dibuat' if created else 'sudah ada (password disetel ulang)', '| user:', u.username, '| grup:', list(u.groups.values_list('name', flat=True)), '| superuser:', u.is_superuser)
" 2>&1 | grep -v 'objects imported' | tail -n 3)

sec "UJI IZIN"
API=http://127.0.0.1:8081
TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d "{\"username\":\"$OCS_AGENT_USER\",\"password\":\"$OCS_AGENT_PWD\"}" "$API/api-auth/token" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))' 2>/dev/null)
fail=0
if [ -n "$TOKEN" ]; then echo "login token agent: OK"; else echo "!! login agent gagal"; fail=1; fi
c() { curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Token $TOKEN" "$@"; }
printf '%-26s -> %s\n' "GET /myaccount/"        "$(c "$API/myaccount/")"
printf '%-26s -> %s (harap 403)\n' "GET /permission/" "$(c "$API/permission/")"
printf '%-26s -> %s (harap 403)\n' "GET /group/"      "$(c "$API/group/")"
printf '%-26s -> %s\n' "GET /template/"         "$(c "$API/template/")"
echo "-- izin efektif akun agent:"
curl -s -H "Authorization: Token $TOKEN" "$API/myaccount/" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin); print("  ", d.get("username"), sorted(d.get("full_permissions", [])))
except Exception as e: print("  (tidak terbaca)", e)'
curl -s -o /dev/null -X POST -H "Authorization: Token $TOKEN" "$API/api-auth/token/logout"

exit "$fail"
