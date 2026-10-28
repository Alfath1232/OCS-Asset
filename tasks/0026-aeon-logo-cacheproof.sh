#!/bin/bash
# 0026-aeon-logo-cacheproof.sh
# User tidak melihat logo AEON padahal file di server sudah terganti -> dugaan cache
# di proxy/CDN untuk nama file tetap (assets/logo-white-*.png).
# 1) Cek apa yang disajikan domain publik vs file lokal (bukti cache)
# 2) Sajikan logo & favicon dari URL baru /aeon/... bernomor versi (dipasang lewat CSS)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_DIR/branding/aeon-ocs3"
F=/usr/share/ocsinventory-frontend
DOMAIN=ocsaeon.itcnelita.com
VER=$(git -C "$REPO_DIR" log -1 --format=%h -- branding/aeon-ocs3 2>/dev/null || date +%s)
LOGO=$(ls "$F"/assets/logo-white-*.png | head -1); LOGO_URL=${LOGO#$F}
ILLU=$(ls "$F"/assets/illu_communaute-*.png | head -1); ILLU_URL=${ILLU#$F}

echo "##### 1) DOMAIN PUBLIK vs FILE LOKAL #####"
for u in "$LOGO_URL" "$ILLU_URL" /favicon.ico; do
  lf="$F$u"
  lm=$(md5sum "$lf" | cut -c1-12)
  hdr=$(curl -s -m 15 -D - -o /tmp/ocsaeon-pub.bin "https://${DOMAIN}${u}" | tr -d '\r')
  pm=$(md5sum /tmp/ocsaeon-pub.bin 2>/dev/null | cut -c1-12)
  code=$(echo "$hdr" | awk 'NR==1{print $2}')
  cache=$(echo "$hdr" | grep -i -E '^(cf-cache-status|x-cache|age|cache-control|server):' | tr '\n' ' ')
  printf '%-40s lokal=%s publik=%s http=%s %s\n' "$u" "$lm" "${pm:--}" "${code:--}" "$( [ "$lm" = "$pm" ] && echo SAMA || echo BEDA)"
  echo "    header: ${cache:-(tidak ada)}"
done
rm -f /tmp/ocsaeon-pub.bin

echo
echo "##### 2) PASANG LOGO DI URL BARU #####"
set -e
install -d -m 755 -o www-data -g www-data "$F/aeon"
install -m 644 -o www-data -g www-data "$SRC/header-logo.png" "$F/aeon/header-logo.png"
install -m 644 -o www-data -g www-data "$SRC/login-logo.png"  "$F/aeon/login-logo.png"
install -m 644 -o www-data -g www-data "$SRC/favicon.ico"     "$F/aeon/favicon.ico"
sed "s/__AEON_VER__/${VER}/g" "$SRC/aeon.css" > "$F/aeon/aeon.css"
chown www-data:www-data "$F/aeon/aeon.css"; chmod 644 "$F/aeon/aeon.css"
grep -c "v=${VER}" "$F/aeon/aeon.css" | xargs echo "referensi logo bernomor versi di CSS:"

python3 - "$F/index.html" "$VER" <<'PY'
import re, sys
p, ver = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r'<link rel="icon"[^>]*>', f'<link rel="icon" href="/aeon/favicon.ico?v={ver}">', s)
s = re.sub(r'href="/aeon/aeon\.css[^"]*"', f'href="/aeon/aeon.css?v={ver}"', s)
open(p, "w").write(s)
PY
chown www-data:www-data "$F/index.html"
cat "$F/index.html"

echo
echo "##### 3) VERIFIKASI #####"
fail=0
H=(-H "Host: ${DOMAIN}" -H "X-Forwarded-Proto: https")
for u in "/aeon/aeon.css?v=${VER}" "/aeon/header-logo.png?v=${VER}" "/aeon/login-logo.png?v=${VER}" "/aeon/favicon.ico?v=${VER}"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "http://localhost$u")
  printf '%-44s -> %s\n' "$u" "$code"; [ "$code" = "200" ] || fail=1
done
echo "-- lewat domain publik:"
for u in "/aeon/header-logo.png?v=${VER}" "/aeon/login-logo.png?v=${VER}"; do
  printf '%-44s -> %s\n' "$u" "$(curl -s -m 15 -o /dev/null -w '%{http_code}' "https://${DOMAIN}$u")"
done
exit "$fail"
