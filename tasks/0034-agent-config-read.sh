#!/bin/bash
# 0034-agent-config-read.sh — BACA SAJA: konfigurasi yang dikirim server ke agent
# (frequency = jeda lapor dalam jam, inventory_checksum, dll) dari /asset/configs/
set -uo pipefail
. /root/ocsaeon-secrets/ocs3-agent.env
API=http://127.0.0.1:8081
TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d "{\"username\":\"$OCS_AGENT_USER\",\"password\":\"$OCS_AGENT_PWD\"}" "$API/api-auth/token" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))')
echo "== /asset/configs/ (yang diterima agent)"
curl -s -H "Authorization: Token $TOKEN" "$API/asset/configs/" | python3 -m json.tool
curl -s -o /dev/null -X POST -H "Authorization: Token $TOKEN" "$API/api-auth/token/logout"
echo
echo "== definisi di source backend"
grep -rn -i -E "frequency|inventory_checksum" /usr/share/ocsinventory-backend/asset/agent_config/*.py \
  /usr/share/ocsinventory-backend/asset/agent_config/migrations/*.py 2>/dev/null | head -20
echo
echo "== aset yang sudah masuk"
. /root/ocsaeon-secrets/ocs3-db.env
mariadb -u "$OCS3_DB_USER" -p"$OCS3_DB_PWD" "$OCS3_DB_NAME" -e "SELECT COUNT(*) AS jumlah_aset FROM inventory_base_inventorybase;" 2>&1
