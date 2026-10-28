#!/bin/bash
# 0027-agent-account.sh
# Persiapan agent OCS 3:
# 1) Lihat izin grup bawaan AgentInventory
# 2) Buat akun khusus agent "ocs-agent" di grup AgentInventory (password acak,
#    disimpan HANYA di server: /root/ocsaeon-secrets/ocs3-agent.env, tidak dicetak)
# 3) Uji: akun agent bisa login, tapi TIDAK bisa membuka data admin
# 4) Cari installer agent terbaru di GitHub, sediakan di server untuk PC kantor
#
# Rollback akun: hapus user ocs-agent dari User management di web console.
set -uo pipefail
sec() { echo; echo "##### $* #####"; }

B=/usr/share/ocsinventory-backend
VENV=/usr/lib/ocsinventory-backend/venv
F=/usr/share/ocsinventory-frontend
SECRET=/root/ocsaeon-secrets/ocs3-agent.env
manage() { (cd "$B" && sudo -u www-data "$VENV/bin/python3" manage.py "$@"); }

sec "1) IZIN GRUP AgentInventory"
manage shell -c "
from django.contrib.auth.models import Group
for g in Group.objects.filter(name__startswith='Agent'):
    print(g.name, '->', sorted(g.permissions.values_list('codename', flat=True)))
" 2>&1 | tail -n 5

sec "2) AKUN AGENT"
if [ ! -f "$SECRET" ]; then
  ( umask 077; printf 'OCS_AGENT_USER=ocs-agent\nOCS_AGENT_PWD=%s\n' "$(openssl rand -hex 12)" > "$SECRET" )
fi
chmod 600 "$SECRET"; . "$SECRET"
OCS_AGENT_USER="$OCS_AGENT_USER" OCS_AGENT_PWD="$OCS_AGENT_PWD" manage shell -c "
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
print('dibuat' if created else 'sudah ada (password disetel ulang)', '| grup:', list(u.groups.values_list('name', flat=True)), '| superuser:', u.is_superuser)
" 2>&1 | tail -n 3
echo "password tersimpan di $SECRET (lihat via SSH: sudo cat $SECRET)"

sec "3) UJI IZIN AKUN AGENT"
API=http://127.0.0.1:8081
TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d "{\"username\":\"$OCS_AGENT_USER\",\"password\":\"$OCS_AGENT_PWD\"}" "$API/api-auth/token" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))' 2>/dev/null)
fail=0
if [ -n "$TOKEN" ]; then echo "login token agent: OK"; else echo "!! login agent gagal"; fail=1; fi
c() { curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Token $TOKEN" "$@"; }
printf '%-28s -> %s (harap 403: bukan haknya)\n' "GET /user/"   "$(c "$API/user/")"
printf '%-28s -> %s (harap 403: bukan haknya)\n' "GET /config/" "$(c "$API/config/")"
printf '%-28s -> %s (endpoint kirim inventaris)\n' "GET /asset/collection/" "$(c "$API/asset/collection/")"
curl -s -o /dev/null -X POST -H "Authorization: Token $TOKEN" "$API/api-auth/token/logout"

sec "4) INSTALLER AGENT DARI GITHUB"
REL=$(curl -s https://api.github.com/repos/OCSInventory-NG/OCSInventory-Agent-Rework/releases?per_page=5)
echo "$REL" | python3 -c '
import sys, json
for r in json.load(sys.stdin):
    print("==", r["tag_name"], r["published_at"][:10], "prerelease" if r["prerelease"] else "stable")
    for a in r["assets"]:
        print("   ", a["name"], a["size"], a["browser_download_url"])
'
WIN_URL=$(echo "$REL" | python3 -c '
import sys, json
r = json.load(sys.stdin)[0]
c = [a["browser_download_url"] for a in r["assets"] if a["name"].lower().endswith(".exe")]
print(c[0] if c else "")
')
if [ -n "$WIN_URL" ]; then
  D="$F/aeon/agent"; install -d -m 755 -o www-data -g www-data "$D"
  NAME=$(basename "$WIN_URL")
  curl -fsSL -o "$D/$NAME" "$WIN_URL" && chown www-data: "$D/$NAME" && chmod 644 "$D/$NAME"
  ls -l "$D"; sha256sum "$D/$NAME"
  printf 'unduh dari LAN: http://192.168.100.122/aeon/agent/%s -> %s\n' "$NAME" \
    "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1/aeon/agent/$NAME")"
else
  echo "!! installer Windows (.exe) tidak ditemukan di rilis terbaru"
fi

sec "5) JANGKAUAN ENDPOINT AGENT"
for u in http://192.168.100.122:8081/api-check/ http://100.105.251.78:8081/api-check/; do
  printf '%-44s -> %s\n' "$u" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$u")"
done

exit "$fail"
